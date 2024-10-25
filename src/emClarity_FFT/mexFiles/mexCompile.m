function [] = mexCompile(varargin)

fprintf("\n\nCompile here\n\n");
mexPATH = '~/Documents/MATLAB/emClarity-master/mexFiles/';%/emClarity/mexFiles/';
% For now just included everything in total.
inc = {'rotation_matrix.cpp','ctf.cu'};
for i = 1:length(inc)
  inc{i} = sprintf('%sutils/%s',mexPATH,inc{i});
end
% mexFILE = 'mexFFT';
if nargin > 0
  mexFILE = varargin;
else
  mexFILE = {'mexCTF','mexFFT','mexXform2d'};
end

mexcuda_opts = { ...
'-lcublas'          ...            % Link to cuBLAS
'-lmwlapack'        ...            % Link to LAPACK
'-lcufft'           ...            % Link to cuFFT
'NVCCFLAGS= -Wno-deprecated-gpu-targets --use_fast_math' ...% the optimizations are default anyway when I checked 
'-L/usr/local/cuda-10.0/lib64' ...
'-L/usr/local/cuda-10.0/nvvm/lib64'};
% '-L/groups/grigorieff/home/himesb/thirdParty/cuda-10.0/lib64'   ...    % Location of CUDA libraries
% '-L/groups/grigorieff/home/himesb/thirdParty/cuda-10.0/nvvm/lib64'};


% '-L/usr/local/cuda-9.1/lib64'   ...    % Location of CUDA libraries
% '-L/usr/local/cuda-9.1/nvvm/lib64'};
% '-L/groups/grigorieff/home/himesb/thirdParty/cuda-8.0/lib64'   ...    % Location of CUDA libraries
% '-L/groups/grigorieff/home/himesb/thirdParty/cuda-8.0/nvvm/lib64'};



for i=1:length(mexFILE)
  
  mexcuda(mexcuda_opts{:}, sprintf('%s%s.cu',mexPATH,mexFILE{i}), inc{1}, inc{2});

  system(sprintf('mv %s.mexa64 %s/compiled/',mexFILE{i}, mexPATH));
end
% end

%nvcc -ptx --library-path /groups/grigorieff/home/himesb/thirdParty/cuda-9.2/nvvm/lib64



