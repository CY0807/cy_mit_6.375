import ClientServer::*;
import GetPut::*;

import FixedPoint::*;

import Complex::*;
import ComplexMP::*;

import Vector::*;
import FIFO::*;

import Cordic::*;

typedef Server#(
    Vector#(bsize, Complex#(FixedPoint#(isize, fsize))),
    Vector#(bsize, ComplexMP#(isize, fsize, psize))
) ToMP#(numeric type bsize, numeric type isize, numeric type fsize, numeric type psize);

typedef Server#(
    Vector#(bsize, ComplexMP#(isize, fsize, psize)),
    Vector#(bsize, Complex#(FixedPoint#(isize, fsize)))
) FromMP#(numeric type bsize, numeric type isize, numeric type fsize, numeric type psize);

module mkToMP(
    ToMP#(bsize, isize, fsize, psize) ifc
);

    Reg#(Bit#(TLog#(bsize))) cnt_req <- mkReg(0);
    Reg#(Bit#(TLog#(bsize))) cnt_rsp <- mkReg(0);

    FIFO#(Vector#(bsize, Complex#(FixedPoint#(isize, fsize))))inq <- mkFIFO();
    FIFO#(Vector#(bsize, ComplexMP#(isize, fsize, psize))) outq <- mkFIFO();

    Reg#(Vector#(bsize, ComplexMP#(isize, fsize, psize))) out_buf <- mkReg(replicate(cmplxmp(0, tophase(0))));

    ToMagnitudePhase#(isize, fsize, psize) convertor <- mkCordicToMagnitudePhase();

    rule do_convert_req;
        convertor.request.put(inq.first[cnt_req]);  //implicity condition'
        if (cnt_req == fromInteger(valueOf(bsize) - 1)) begin
            inq.deq;
            cnt_req <= 0;
        end else begin 
            cnt_req <= cnt_req + 1;
        end
    endrule

    rule get_convert_resp;
        let got <- convertor.response.get(); //implicity condition
        out_buf[cnt_rsp] <= got;
        
        if (cnt_rsp == fromInteger(valueOf(bsize) - 1)) begin
            cnt_rsp <= 0;
            let t = out_buf;
            t[cnt_rsp] = got;
            outq.enq(t);
        end else begin 
            cnt_rsp <= cnt_rsp + 1;
        end
    endrule

    interface Put request = toPut(inq);
    interface Get response = toGet(outq);
endmodule



module mkFromMP(
    FromMP#(bsize, isize, fsize, psize) ifc
);

    Reg#(Bit#(TLog#(bsize))) cnt_req <- mkReg(0);
    Reg#(Bit#(TLog#(bsize))) cnt_rsp <- mkReg(0);

    FIFO#(Vector#(bsize, Complex#(FixedPoint#(isize, fsize))))outq <- mkFIFO();
    FIFO#(Vector#(bsize, ComplexMP#(isize, fsize, psize)))inq <- mkFIFO();

    Reg#(Vector#(bsize, Complex#(FixedPoint#(isize, fsize)))) out_buf <- mkRegU();

    FromMagnitudePhase#(isize, fsize, psize) convertor <- mkCordicFromMagnitudePhase();

    rule do_convert_req;
        convertor.request.put(inq.first[cnt_req]);  //implicity condition'
        if (cnt_req == fromInteger(valueOf(bsize) - 1)) begin
            inq.deq;
            cnt_req <= 0;
        end else begin 
            cnt_req <= cnt_req + 1;
        end
    endrule

    rule get_convert_resp;

        let got <- convertor.response.get(); //implicity condition
        out_buf[cnt_rsp] <= got;
        
        if (cnt_rsp == fromInteger(valueOf(bsize) - 1)) begin
            cnt_rsp <= 0;
            let t = out_buf;
            t[cnt_rsp] = got;
            outq.enq(t);
        end else begin 
            cnt_rsp <= cnt_rsp + 1;
        end
    endrule

    interface Put request = toPut(inq);
    interface Get response = toGet(outq);

endmodule
