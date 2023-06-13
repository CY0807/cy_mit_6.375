import FFT::*;
import Randomizable::*;
import Vector::*;
import AudioProcessorTypes::*;
import Complex::*;
import FixedPoint::*;
import Reg6375::*;
import ClientServer::*;
import GetPut::*;

(* synthesize *)
module mkTbIFFT(Empty);
    FFT fft <- mkFFT();
    FFT ifft <- mkIFFT();
    Vector#(FFT_POINTS, Randomize#(Bit#(16))) randomVal1 <- replicateM(mkGenericRandomizer);
    Vector#(FFT_POINTS, Randomize#(Bit#(16))) randomVal2 <- replicateM(mkGenericRandomizer);
    Vector#(FFT_POINTS, Randomize#(Bit#(16))) randomVal3 <- replicateM(mkGenericRandomizer);
    Vector#(FFT_POINTS, Randomize#(Bit#(16))) randomVal4 <- replicateM(mkGenericRandomizer);
    Reg#(int) cycle <- mkReg(0);
    Reg#(Bool) init <- mkReg(False);
    Reg#(Bool) feedFftDone <- mkReg(False);
    Reg#(Bool) feedIfft_done <- mkReg(False);

    rule initialize (init == False);
        for (Integer i=0; i < valueOf(FFT_POINTS); i=i+1) begin
            randomVal1[i].cntrl.init;
            randomVal2[i].cntrl.init;
            randomVal3[i].cntrl.init;
            randomVal4[i].cntrl.init;
        end
        init <= True;
        $display("\n Test Start");
    endrule

    rule feedFft (init && (feedFftDone == False));
        feedFftDone <= True;
        $display("Input Data:");
        FixedPoint#(16,16) data1 = 0;
        FixedPoint#(16,16) data2 = 0;

        Vector#(FFT_POINTS, ComplexSample) input_data;
        for (Integer i=0; i < valueOf(FFT_POINTS); i=i+1) begin
            let temp1_1 <- randomVal1[i].next;
            let temp1_2 <- randomVal2[i].next;
            let temp2_1 <- randomVal3[i].next;
            let temp2_2 <- randomVal4[i].next;
            data1 = unpack({temp1_1, temp1_2});
            data2 = unpack({temp2_1, temp2_2});
            input_data[i] = cmplx(data1, data2);
            $write("%d, ", input_data[i]);
        end
        fft.request.put(input_data);
        $write("\n");
    endrule

    rule readFft_feedIfft (init && (feedIfft_done == False) && feedFftDone);
        feedIfft_done <= True;
        let x <- fft.response.get();
        $display("\nFFT Output Data:");
        for (Integer i=0; i < valueOf(FFT_POINTS); i=i+1) begin
            $write("%d ", x[i]);
        end
        ifft.request.put(x);
        $write("\n");
    endrule

    rule readIfft(feedIfft_done);
        let x <- ifft.response.get();
        $display("\nFFT Output Data:");
        for (Integer i=0; i < valueOf(FFT_POINTS); i=i+1) begin
            $write("%d ", x[i]);
        end
        $write("\n");
        $finish;
    endrule

    rule padFft(init && feedFftDone);
        Vector#(FFT_POINTS, ComplexSample) input_data;
        for (Integer i=0; i < valueOf(FFT_POINTS); i=i+1) begin
            input_data[i] = cmplx(0, 0);
        end
        fft.request.put(input_data);
    endrule

    rule padIfft(init && feedIfft_done);
        Vector#(FFT_POINTS, ComplexSample) input_data;
        for (Integer i=0; i < valueOf(FFT_POINTS); i=i+1) begin
            input_data[i] = cmplx(0, 0);
        end
        ifft.request.put(input_data);
    endrule

    rule timeout(init);
        if(cycle == 512 * 512) begin
            $display("Time Out, Fail\n");
            $finish;
        end
        cycle <= cycle + 1;
    endrule

endmodule