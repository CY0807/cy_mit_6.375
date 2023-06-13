bscflags = -keep-fires -aggressive-conditions
bsvdir = ../common:../fir
build_dir = bscdir
synth_dir = /tmp/6375-lab2-${USER}

src = FFT.bsv

compile: $(src)
	mkdir -p bscdir
	bsc -u -sim -simdir $(build_dir) -bdir $(build_dir) -info-dir $(build_dir) $(bscflags) -p +:$(bsvdir) -g mkTbIFFT ../common/TestDriver.bsv

tbfft: compile
	bsc -e mkTbIFFT -sim -o ./out_tbfft -simdir $(build_dir) -bdir $(build_dir) -info-dir $(build_dir) $(bscflags)
	./out_tbfft

verilog: $(src)
	mkdir -p bscdir
	bsc -u -verilog -elab -vdir $(build_dir) -bdir $(build_dir) -info-dir $(build_dir) $(bscflags) -p +:$(bsvdir) -g mkFFT $^

synth: $(src)
	mkdir -p $(synth_dir)
	synth $^ mkFFT -p $(bsvdir) -s $(synth_dir) -l multisize

clean:
	rm -rf bscdir out out.so
