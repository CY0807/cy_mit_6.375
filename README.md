# Lab1

为FIR滤波程序，核心代码如下：

````
	Vector#(8, Reg#(Sample)) r <- replicateM(mkReg(0));
    Vector#(9, Multiplier) mul <- replicateM(mkMultiplier());

    rule shift_and_mul (True);
        Sample sample = infifo.first();
        infifo.deq();
        r[0] <= sample;
        for (Integer i=0; i<7; i=i+1) begin
            r[i+1] <= r[i];
        end
       mul[0].putOperands(c[0], sample);
       for (Integer i=0; i<8; i=i+1) begin
          mul[i+1].putOperands(c[i+1], r[i]);
       end
    endrule

    rule do_sum;
        FixedPoint#(16,16) accumulate = 0;
        for (Integer i=0; i<9; i=i+1) begin
            let t <- mul[i].getResult;
            accumulate = accumulate + t;
        end
        outfifo.enq(fxptGetInt(accumulate));
    endrule
````

编译仿真程序：

<img src="./image/image-20230611232351103.png" alt="image-20230611232351103" style="zoom:33%;" />

仿真结果：

<img src="./image/image-20230611232759449.png" alt="image-20230611232759449" style="zoom:33%;" />

生成Verilog程序：

<img src="./image/image-20230611235037950.png" alt="image-20230611235037950" style="zoom:33%;" />

# Lab2

实验给出了FFT的combinational实现，要求改为pipeline形式和fold形式。并且通过模块带参数实现不同tap数的多态FIR模块，并通过interface的参数化实现FFT模块的不同point数的多态、任意complex类型的多态。

原始Combinational FFT核心部分：

````
rule comb_fft;
    Vector#(TAdd#(1, TLog#(fft_points)), Vector#(fft_points, Complex#(cmplxd))) stage_data = newVector();
    stage_data[0] = inputFIFO.first();
    inputFIFO.deq();
    for(Integer stage = 0; stage < valueof(TLog#(fft_points)); stage=stage+1) begin
        stage_data[stage+1] = stage_f(fromInteger(stage), stage_data[stage]);  
    end
    outputFIFO.enq(stage_data[valueof(TLog#(fft_points))]);
  endrule
````

Pipeline FFT核心部分：

````
stage_data <- replicateM(mkReg(tagged Invalid));

rule do_fft;
    inputFIFO.deq();
    stage_data[0] <= tagged Valid inputFIFO.first;
    
    for(Integer stage = 0; stage < valueof(TLog#(fft_points)); stage=stage+1) begin
        case (stage_data[stage]) matches
            tagged Valid .data : stage_data[stage+1] <= tagged Valid stage_f(fromInteger(stage), data);
            tagged Invalid:  stage_data[stage+1] <= tagged Invalid;
        endcase
    end

    if (isValid(stage_data[valueof(TLog#(fft_points))]) == True) begin
        outputFIFO.enq(fromMaybe(?, stage_data[valueof(TLog#(fft_points))]));
    end    
  endrule
````

Folded FFT核心部分：

````
rule do_fft;
    Vector#(fft_points, Complex#(cmplxd)) tmp;
    let max_stage = fromInteger(valueOf(TLog#(fft_points))-1);
    stage <= (stage == max_stage)? 0 : stage + 1;

    if (stage == 0) begin
        inputFIFO.deq();
        tmp = stage_f(stage, inputFIFO.first);
        if (first_round == False) begin
            outputFIFO.enq(stage_data);
        end
        first_round <= False;
    end else begin 
        tmp = stage_f(stage, stage_data);
    end

    stage_data <= tmp;   
  endrule
````

编译仿真：

<img src="./image/image-20230612234408275.png" alt="image-20230612234408275" style="zoom:33%;" />

其中初次编译存在warning：

<img src="./image/image-20230612234435051.png" alt="image-20230612234435051" style="zoom:33%;" />

笔者认为是lab自带的combinational FFT的rule中的逻辑太复杂，unfold出来的内容太多导致，但最终能实现验证的功能

仿真结果：

<img src="./image/image-20230612235425967.png" alt="image-20230612235425967" style="zoom:33%;" />

生成verilog：

<img src="./image/image-20230613000407285.png" alt="image-20230613000407285" style="zoom:33%;" />

# Lab3

Pitch Adjust 程序测试仿真：

<img src="./image/image-20230613001247584.png" alt="image-20230613001247584" style="zoom:33%;" />

AutoPipeline 仿真编译：

<img src="./image/image-20230613004744972.png" alt="image-20230613004744972" style="zoom:33%;" />

<img src="./image/image-20230613004802301.png" alt="image-20230613004802301" style="zoom:33%;" />

第一个warning是关于lab自带的cordic的Fshow函数，不影响实际电路功能，第2、3个warning关于combinational FFT，仿真时使用也不影响实际功能。

AutoPipeline 仿真结果：

<img src="./image/image-20230613005148265.png" alt="image-20230613005148265" style="zoom:33%;" />

GetPut Interface总结：

1、是BSV中预定义的interface，提供了自动化握手的功能

<img src="./image/image-20230613101318159.png" alt="image-20230613101318159" style="zoom:33%;" />

2、对于接口和FIFO：

<img src="./image/image-20230613101453063.png" alt="image-20230613101453063" style="zoom:33%;" />

<img src="./image/image-20230613101931624.png" alt="image-20230613101931624" style="zoom:33%;" />

如下两种方式等效：

<img src="./image/image-20230613101435269.png" alt="image-20230613101435269" style="zoom:33%;" />

<img src="./image/image-20230613101509840.png" alt="image-20230613101509840" style="zoom:33%;" />

3、拓展：采用Server实现多态接口

<img src="./image/image-20230613101843496.png" alt="image-20230613101843496" style="zoom:33%;" />

<img src="./image/image-20230613101901858.png" alt="image-20230613101901858" style="zoom:33%;" />

# Lab4

本实验使用了kazutoiris/connectal的docker环境，并在Lab4实验目录下运行如下命令进入环境。

````
sudo docker run -i -t --volume .:/root kazutoiris/connectal
````

connectal simulation 结果：

<img src="./image/image-20230614190706099.png" alt="image-20230614190706099" style="zoom:33%;" />

此外采用了sub interface的方法将 pitch adjuct 的 factor作为可调节的变量输入到模块中。



# Lab5

## 1 MultiCycle

**small benchmark:**

<img src="./image/image-20230630094956569.png" alt="image-20230630094956569" style="zoom:33%;" /><img src="./image/image-20230630095009562.png" alt="image-20230630095009562" style="zoom:33%;" /><img src="./image/image-20230630095022974.png" alt="image-20230630095022974" style="zoom:33%;" /><img src="./image/image-20230630095112331.png" alt="image-20230630095112331" style="zoom:33%;" /><img src="./image/image-20230630095120844.png" alt="image-20230630095120844" style="zoom:33%;" />

**big benchmark:**

<img src="./image/image-20230630100052289.png" alt="image-20230630100052289" style="zoom:33%;" /><img src="./image/image-20230630100108783.png" alt="image-20230630100108783" style="zoom: 33%;" /><img src="./image/image-20230630100127750.png" alt="image-20230630100127750" style="zoom:33%;" /><img src="./image/image-20230630100137373.png" alt="image-20230630100137373" style="zoom:33%;" />

## 2 Two Stage Ehr

**small benchmark:**

<img src="./image/image-20230630105450463.png" alt="image-20230630105450463" style="zoom:33%;" /><img src="./image/image-20230630103542917.png" alt="image-20230630103542917" style="zoom:33%;" /><img src="./image/image-20230630103551392.png" alt="image-20230630103551392" style="zoom:33%;" /><img src="./image/image-20230630103601133.png" alt="image-20230630103601133" style="zoom:33%;" /><img src="./image/image-20230630103612346.png" alt="image-20230630103612346" style="zoom:33%;" />

**big benchmark:**

<img src="./image/image-20230630103638025.png" alt="image-20230630103638025" style="zoom:33%;" /><img src="./image/image-20230630103805640.png" alt="image-20230630103805640" style="zoom:33%;" /><img src="./image/image-20230630110014766.png" alt="image-20230630110014766" style="zoom:33%;" /><img src="./image/image-20230630103824536.png" alt="image-20230630103824536" style="zoom:33%;" />

## 3 Two Stage Redir

**small benchmark:**

<img src="./image/image-20230630112705619.png" alt="image-20230630112705619" style="zoom:33%;" /><img src="./image/image-20230630112717502.png" alt="image-20230630112717502" style="zoom:33%;" /><img src="./image/image-20230630112725548.png" alt="image-20230630112725548" style="zoom:33%;" /><img src="./image/image-20230630112738571.png" alt="image-20230630112738571" style="zoom:33%;" /><img src="./image/image-20230630112749566.png" alt="image-20230630112749566" style="zoom:33%;" />

**big benchmark:**

<img src="./image/image-20230630112805696.png" alt="image-20230630112805696" style="zoom:33%;" /><img src="./image/image-20230630112817373.png" alt="image-20230630112817373" style="zoom:33%;" /><img src="./image/image-20230630112829972.png" alt="image-20230630112829972" style="zoom:33%;" /><img src="./image/image-20230630112839923.png" alt="image-20230630112839923" style="zoom:33%;" />

## 4 Two Stage BTB

**small benchmark:**

<img src="./image/image-20230630115314295.png" alt="image-20230630115314295" style="zoom:33%;" /><img src="./image/image-20230630115327745.png" alt="image-20230630115327745" style="zoom:33%;" /><img src="./image/image-20230630115344833.png" alt="image-20230630115344833" style="zoom:33%;" /><img src="./image/image-20230630115354171.png" alt="image-20230630115354171" style="zoom:33%;" /><img src="./image/image-20230630115403525.png" alt="image-20230630115403525" style="zoom:33%;" />

**big benchmark:**

<img src="./image/image-20230630115428349.png" alt="image-20230630115428349" style="zoom:33%;" /><img src="./image/image-20230630115438032.png" alt="image-20230630115438032" style="zoom:33%;" /><img src="./image/image-20230630115446772.png" alt="image-20230630115446772" style="zoom:33%;" /><img src="./image/image-20230630115454648.png" alt="image-20230630115454648" style="zoom:33%;" />
