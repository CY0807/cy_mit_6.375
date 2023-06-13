
import Counter::*;

import AudioPipeline::*;
import AudioProcessorTypes::*;

(* synthesize *)
module mkTestDriver (Empty);

    AudioProcessor pipeline <- mkAudioPipeline();

    Reg#(File) m_in <- mkRegU();
    Reg#(File) m_out <- mkRegU();

    Reg#(Bool) m_inited <- mkReg(False);
    Reg#(Bool) m_doneread <- mkReg(False);

    Counter#(32) m_outstanding <- mkCounter(0);

    rule init(!m_inited);
        m_inited <= True;

        File in <- $fopen("in.pcm", "rb");
        if (in == InvalidFile) begin
            $display("couldn't open in.pcm");
            $finish;
        end
        m_in <= in;

        File out <- $fopen("out.pcm", "wb");
        if (out == InvalidFile) begin
            $display("couldn't open out.pcm for write");
            $finish;
        end
        m_out <= out;
        $display("test start");
    endrule

    rule read(m_inited && !m_doneread && m_outstanding.value() != maxBound);
        int a <- $fgetc(m_in);
        int b <- $fgetc(m_in);

        if (a == -1 || b == -1) begin
            m_doneread <= True;
            $fclose(m_in);
        end else begin
            Bit#(8) a8 = truncate(pack(a));
            Bit#(8) b8 = truncate(pack(b));

            // Input is little endian. That means the first byte we read (a8)
            // is the least significant byte in the sample.
            pipeline.putSampleInput(unpack({b8, a8}));
            m_outstanding.up();
        end
    endrule

    (* descending_urgency="write, pad" *)
    rule pad(m_inited && m_doneread);
        // In case there aren't an FFT_POINTs multiple of input samples, pad
        // the rest with zeros so eventually all the outstanding samples will
        // drain.
        pipeline.putSampleInput(0);
    endrule

    rule write(m_inited);
        Sample d <- pipeline.getSampleOutput();
        m_outstanding.down();

        // Little endian: first thing out is least significant.
        Bit#(8) a8 = pack(d)[7:0];
        Bit#(8) b8 = pack(d)[15:8];
        $fwrite(m_out, "%c", a8);
        $fwrite(m_out, "%c", b8);
    endrule

    rule finish(m_doneread && m_outstanding.value() == 0);
        $fclose(m_out);
        $display("write complete");
        $finish();
    endrule

    rule print_clock;
        //$display("============");
    endrule

endmodule

// TestBench used to check FFT and IFFT data

import Randomizable::*;
import ClientServer::*;
import GetPut::*;
import AudioProcessorTypes::*;
import FFT::*;
import FixedPoint::*;
import Vector::*;
import Complex::*;
import FIFO::*;
import FIFOF::*;
import DReg::*;

(* synthesize *)
module mkTbIFFT(Empty);
    FFT#(FFT_POINTS, FixedPoint#(16, 16)) fft <- mkFFT();
    FFT#(FFT_POINTS, FixedPoint#(16, 16)) ifft <- mkIFFT();
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