import Types::*;
import ProcTypes::*;
import MemTypes::*;
import RFile::*;
import Scoreboard::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import FIFO::*;
import MemUtil::*;
import ClientServer::*;
import Ehr::*;
import GetPut::*;

import Cache::*;
import Fifo::*;
import MemInit::*;
import CacheTypes::*;

typedef struct {
Word pc;
Word ppc;
Bool epoch;
} F2D deriving(Bits, Eq);

typedef struct {
Word pc;
Word ppc;
Bool epoch;
DecodedInst dInst;
Word rVal1;
Word rVal2;
} D2E deriving(Bits, Eq);


module mkProc#(Fifo#(2, DDR3_Req) ddr3ReqFifo, Fifo#(2, DDR3_Resp) ddr3RespFifo)(Proc);
////////////////////////////////////////////////////////////////////////////////
/// Processor module instantiation
////////////////////////////////////////////////////////////////////////////////
    Ehr#(2,Word) pc    <- mkEhr(0);
    //Ehr#(2,Bool) epoch <- mkEhr(False);
    Reg#(Bool) epoch <- mkReg(False);
    RFile      rf    <- mkBypassRFile;
    CsrFile    csrf  <- mkCsrFile;

    Fifo#(2,F2D) f2d <- mkCFFifo;
    Fifo#(2,D2E) d2e <- mkCFFifo;

    Reg#(Bool)  loadWaitReg <- mkReg(False);
    Reg#(RIndx) dstLoad <- mkReg(0);

    Ehr#(2, Maybe#(Addr)) exeRedirect <- mkEhr(Invalid);

    Reg#(Maybe#(Word))  fetchedInst <- mkReg(Invalid);
    Scoreboard#(6)  sb <- mkCFScoreboard;

    Reg#(Bit#(32)) cycle <- mkReg(0);


////////////////////////////////////////////////////////////////////////////////
/// Section: Memory Subsystem
////////////////////////////////////////////////////////////////////////////////

    Bool                        memReady    =  True;
    let                         wideMem     <- mkWideMemFromDDR3(ddr3ReqFifo,ddr3RespFifo);
    Vector#(2, WideMem)         splitMem    <- mkSplitWideMem(memReady && csrf.started, wideMem);

    Cache iMem <- mkCache( splitMem[1] );
    Cache dMem <- mkCache( splitMem[0] );

    rule drainMemResponses( !csrf.started );
        $display("drain!");
        ddr3RespFifo.deq;
    endrule

    rule drainScoreBoard( !csrf.started );
        $display("drain!");
        sb.remove;
    endrule

////////////////////////////////////////////////////////////////////////////////
/// End of Section: Memory Subsystem
////////////////////////////////////////////////////////////////////////////////
    rule cycleCounter(csrf.started);
        cycle <= cycle + 1;
        /*
        $fwrite(stderr, "Cycle %d -------------------------\n", cycle);
        if(cycle >= 300) begin
            $fwrite(stderr, "\n test finish, exit\n");
            $finish;
        end
        */
    endrule

////////////////////////////////////////////////////////////////////////////////
/// Begin of Section: Processor
////////////////////////////////////////////////////////////////////////////////
    rule doFetch if (csrf.started);
        let ppc = pc[0] + 4;
        iMem.req(MemReq{op: Ld, addr: pc[0], data: ?});
        pc[0] <= ppc;
        f2d.enq(F2D {pc: pc[0], ppc: ppc, epoch: epoch});
        //$fwrite(stderr, "[%d] doFetch\n", cycle);
    endrule


    rule doDecode if(csrf.started);
////////////////////////////////////////////////////////////////////////////////
/// Student's Task : Issue 1
/// Fix the code in this rule such that no new instruction
/// should be fetched in the stalled state
////////////////////////////////////////////////////////////////////////////////
        //$fwrite(stderr, "[%d] doDecode\n", cycle);
        Data inst;
        if(isValid(fetchedInst)) begin
            inst=fromMaybe(?,fetchedInst);
        end else begin
            inst<-iMem.resp();
        end
        //let inst <- iMem.resp();

        // Uncomment the following to have a pretty instruction print for debugging
        // $display(showInst(inst));

        let x = f2d.first;
        let epochD = x.epoch;
        if (epochD == epoch) begin  // right-path instruction
            let dInst = decode(inst); // rs1, rs2 are Maybe types
            // check for data hazard
            let hazard = (sb.search1(dInst.src1) || sb.search2(dInst.src2));
            // if no hazard detected
            if (!hazard) begin
                let rVal1 = rf.rd1(fromMaybe(?, dInst.src1));
                let rVal2 = rf.rd2(fromMaybe(?, dInst.src2));
                sb.insert(dInst.dst); // for detecting future data hazards
                d2e.enq(D2E {pc: x.pc, ppc: x.ppc, epoch: x.epoch,
                dInst: dInst, rVal1: rVal1, rVal2: rVal2});
                f2d.deq;
                fetchedInst <= tagged Invalid;
            end
            // if hazard detected
            else begin
                fetchedInst <= tagged Valid inst;
                //$fwrite(stderr, "[%d] doDecode data hazard\n", cycle);
            end
        end
        else begin // wrong-path instruction
            f2d.deq;
            fetchedInst <= tagged Invalid;
        end
    endrule

    
    rule doExecute(!loadWaitReg && csrf.started);
////////////////////////////////////////////////////////////////////////////////
/// Student's Task: Issue 2
/// Fix the code in this rule by removing item from scoreboard when
/// an instruction completes execution
////////////////////////////////////////////////////////////////////////////////
        //$fwrite(stderr, "[%d] do Execute\n", cycle);
        let x = d2e.first;
        let pcE = x.pc; let ppc = x.ppc; let epochE = x.epoch;
        let rVal1 = x.rVal1; let rVal2 = x.rVal2;
        let dInst = x.dInst;
        d2e.deq;


        // read CSR values (for CSRR inst)
        Word csrVal = csrf.rd(fromMaybe(?, dInst.csr));

        // execute
        ExecInst eInst = exec(dInst, rVal1, rVal2, pcE, ppc, csrVal);

        if(!(epochE == epoch && eInst.iType == Ld)) begin
            sb.remove;
        end

        if (epochE == epoch) begin  // right-path instruction
            if(dInst.iType == Unsupported) begin
                $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", pcE);
                $finish;
            end

////////////////////////////////////////////////////////////////////////////////
/// Student's Task: Issue 3
/// Modifying the following code section to fix doFetch and doExecute rule conflicts
////////////////////////////////////////////////////////////////////////////////
            let misprediction = eInst.mispredict;
            if ( misprediction ) begin
                // redirect the pc
                let jump = eInst.iType == J || eInst.iType == Jr || eInst.iType == Br;
                let npc = jump? eInst.addr : pcE+4;
                exeRedirect[0] <= Valid(npc);
            end
////////////////////////////////////////////////////////////////////////////////
/// End of code section for Student's Task: Issue 3
////////////////////////////////////////////////////////////////////////////////

            if (eInst.iType == Ld) begin
                dMem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
                dstLoad <= fromMaybe(?, eInst.dst);
                loadWaitReg <= True;
            end
            else if (eInst.iType == St) begin
                dMem.req(MemReq{op: St, addr: eInst.addr,
                data: eInst.data});
            end
            else begin
                if(isValid(eInst.dst)) begin
                    rf.wr(fromMaybe(?, eInst.dst), eInst.data);
                end
            end

            csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);

        end
    endrule

    rule doLoadWait(loadWaitReg);
////////////////////////////////////////////////////////////////////////////////
/// Student's Task: Issue 2
/// Fix the code in this rule by removing item from scoreboard when
/// an instruction completes execution
////////////////////////////////////////////////////////////////////////////////
        //$fwrite(stderr, "[%d] LoadWait\n", cycle);
        let data <- dMem.resp();
        rf.wr(dstLoad, data);
        loadWaitReg <= False;
        sb.remove;
    endrule

    (* fire_when_enabled *)
	rule cononicalizeRedirect(csrf.started);
        if(exeRedirect[1] matches tagged Valid .r) begin
            pc[1] <= r;
            epoch <= !epoch;
        end
        exeRedirect[1] <= Invalid;
        //$fwrite(stderr, "[%d] do cononicalize\n", cycle);
    endrule


    method ActionValue#(CpuToHostData) cpuToHost;
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Action hostToCpu(Bit#(32) startpc) if ( !csrf.started && memReady );
        csrf.start(0); // only 1 core, id = 0
        $display("Start at pc 200\n");
        $fflush(stdout);
        pc[0] <= startpc;
    endmethod

endmodule

