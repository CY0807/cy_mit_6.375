
import ClientServer::*;
import FIFO::*;
import GetPut::*;

import FixedPoint::*;
import Vector::*;

import ComplexMP::*;


typedef Server#(
    Vector#(nbins, ComplexMP#(isize, fsize, psize)),
    Vector#(nbins, ComplexMP#(isize, fsize, psize))
) PitchAdjust#(numeric type nbins, numeric type isize, numeric type fsize, numeric type psize);

interface SettablePitchAdjust#(numeric type nbins, numeric type isize, numeric type fsize, numeric type psize);
    interface PitchAdjust#(nbins, isize, fsize, psize) adjust;
    interface Put#(FixedPoint#(isize, fsize)) setFactor;
endinterface


// s - the amount each window is shifted from the previous window.
//
// factor - the amount to adjust the pitch.
//  1.0 makes no change. 2.0 goes up an octave, 0.5 goes down an octave, etc...
module mkPitchAdjust(Integer s, SettablePitchAdjust#(nbins, isize, fsize, psize) ifc) provisos(
    Add#(a__, TLog#(nbins), isize),
    Add#(psize, b__, isize),
    Add#(c__, psize, TAdd#(isize, isize))
);

    FIFO#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) inp <- mkFIFO();
    FIFO#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) outp <- mkFIFO();

    Reg#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) in <- mkRegU();
    Reg#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) out <- mkRegU();

    Reg#(Vector#(nbins, Phase#(psize))) inphases <- mkReg(replicate(tophase(0)));
    Reg#(Vector#(nbins, Phase#(psize))) outphases <- mkReg(replicate(tophase(0)));

    Reg#(Bool) input_ready <- mkReg(True);
    Reg#(Bool) output_ready <- mkReg(False);
    Reg#(Bit#(TLog#(nbins))) cnt <- mkReg(0);

    Reg#(Maybe#(FixedPoint#(isize, fsize)) ) _factor <- mkReg(tagged Invalid);

    rule get_input(input_ready && (!output_ready));
        input_ready <= False;
        in <= inp.first;
        inp.deq;
        out <= unpack(0);
    endrule

    rule get_output(output_ready);
        output_ready <= False;
        outp.enq(out);
    endrule

    rule run (!(input_ready || output_ready));
        if(cnt == fromInteger(valueOf(nbins)-1)) begin
            input_ready <= True;
            output_ready <= True;
            cnt <= 0;
        end
        else begin
            cnt <= cnt + 1;
        end

        let phase = in[cnt].phase;
        let mag = in[cnt].magnitude;  
        let dphase = phase - inphases[cnt];
        inphases[cnt] <= phase;

        Bit#(isize) t = zeroExtend(cnt);
        FixedPoint#(isize, fsize) fp_cnt = fromInt(unpack(t));

        let bin = fxptGetInt(fp_cnt * factor);
        let nbin = fxptGetInt((fp_cnt+1) * factor);

        if (nbin != bin && bin >= 0 && bin < fromInteger(valueOf(nbins))) begin
            FixedPoint#(isize, fsize) fp_dphase = fromInt(dphase);
            Phase#(psize) shifted = truncate(fxptGetInt(fxptMult(fp_dphase, factor)));
            let outphases_tmp = outphases[bin] + shifted;
            outphases[bin] <= outphases_tmp;
            out[bin] <= cmplxmp(mag, outphases_tmp);
        end

    endrule

    interface PitchAdjust adjust;
        interface Put request = toPut(inp);
        interface Get response = toGet(outp);
    endinterface

    interface Put setFactor;
        method Action put(FixedPoint#(isize, fsize) x) if (!isValid(_factor));
            _factor <= tagged Valid x;
        endmethod
    endinterface

endmodule

