function cnn_resnet_fusion(varargin)
%CNN_UCF101FUSION  Demonstrates training a Two-Stream Fusion ConvNet on UCF101
% This module utilizes a pretrained  VGG-VD-16 for rgb and flow
% on UCF101 data for training of the proposed architecture in  our paper
% 
%   Christoph Feichtenhofer, Axel Pinz, Andrew Zisserman
%   "Convolutional Two-Stream Network Fusion for Video Action Recognition"
%   in Proc. CVPR 2016

if ~isempty(gcp('nocreate')),

    delete(gcp)
end

opts = cnn_setup_environment();
opts.train.gpus = [1];
opts.cudnnWorkspaceLimit = [1];

opts.dataSet = 'Remat'; 
  
addpath('network_surgery');
opts.dataDir = fullfile(opts.dataPath, opts.dataSet) ;
opts.splitDir = [opts.dataSet '_splits']; 

opts.inputdim  = [ 224,  224, 3] ;
opts.initMethod = '2sumAB';
opts.dropOutRatio = 0;

% opts.train.fuseFrom = 'temporal';
% opts.train.fuseInto = 'spatial'; 
opts.train.fuseFrom = 'spatial';
opts.train.fuseInto = 'temporal'; 
opts.train.removeFuseFrom = 0 ;
opts.backpropFuseFrom = 1 ;
opts.nSplit = 1 ;
addConv3D = 0 ;
addPool3D = 0 ;
doSum = 1;
doMax = 0;
opts.train.learningRate =  1*[1e-2*ones(1,3) 1e-3*ones(1,4) 1e-4*ones(1,1)  1e-5*ones(1,1) 1e-6*ones(1,2)]  ;
opts.train.cheapResize = 0 ;

nFrames = 1;
model = ['test-angulargradient-res50-relu5-2x-resnet-split=' num2str(opts.nSplit) '-vgg-' opts.initMethod '-pred-3D=' num2str(addConv3D) ...
    '-pool3D=' num2str(addPool3D) ...
    '-fuseInto=' opts.train.fuseInto, ...
    '-removeFuseFrom=' num2str(  opts.train.removeFuseFrom )...
    '-backpropFuseFrom=' num2str(opts.backpropFuseFrom), ...
    '-nFrames=' num2str(nFrames), ...    
    '-dr' num2str(opts.dropOutRatio)];
if ~isempty(opts.train.gpus)
  opts.train.memoryMapFile = fullfile(tempdir, 'ramdisk', ['matconvnet' num2str(opts.train.gpus(1)) '.bin']) ;
end

opts.train.fusionType = 'conv';
opts.train.fusionLayer = {'res5c_relu_spatial', 'res5c_relu_spatial'; };
% opts.train.fusionLayer = {'relu5_3', 'relu5_3'; };

opts.expDir = fullfile(opts.dataDir, [opts.dataSet '-' model]) ;
opts.modelA = fullfile(opts.modelPath, [opts.dataSet '-img-resnet-split' num2str(opts.nSplit) '-dr0.5.mat']) ;
opts.modelB = fullfile(opts.modelPath, [opts.dataSet '-TVL1flow-resnet-split' num2str(opts.nSplit) '-dr0.5.mat']) ;

opts.train.startEpoch = 1;
opts.train.epochStep = 1;
opts.train.epochFactor = 10;
opts.train.numEpochs = length(opts.train.learningRate) ;

[opts, varargin] = vl_argparse(opts, varargin) ;

opts.imdbPath = fullfile(opts.dataDir, [opts.dataSet '_split' num2str(opts.nSplit) 'imdb.mat']);


opts.train.batchSize = 196 ;
opts.train.numSubBatches = 32 / max(numel(opts.train.gpus),1); % lower this number if you have more GPU memory available

opts.train.saveAllPredScores = 0;
opts.train.denseEval = 1;

opts.train.plotDiagnostics = 0 ;
opts.train.continue = 1 ;
opts.train.prefetch = 1 ;
opts.train.expDir = opts.expDir ;

opts.train.numAugments = 1;
opts.train.frameSample = 'random';
opts.train.nFramesPerVid = nFrames;
opts.train.augmentation = 'noCtr';

opts = vl_argparse(opts, varargin) ;

% -------------------------------------------------------------------------
%                                                   Database initialization
% -------------------------------------------------------------------------
if exist(opts.imdbPath)
  imdb = load(opts.imdbPath) ;
  imdb.flowDir = opts.flowDir;
else
  imdb = cnn_Remat_setup_data('dataPath', opts.dataPath, 'flowDir',opts.flowDir, 'nSplit', opts.nSplit) ;
  save(opts.imdbPath, '-struct', 'imdb', '-v6') ;
end

% -------------------------------------------------------------------------
%                                                    Network initialization
% -------------------------------------------------------------------------
netA = load(opts.modelA) ;
netB = load(opts.modelB) ;
if isfield(netA, 'net'), netA=netA.net;end
if isfield(netB, 'net'), netB=netB.net;end
% drop1 = struct('name', 'dropout1', 'type', 'dropout', 'rate' , opts.dropOutRatio) ;
% drop2 = struct('name', 'dropout2', 'type', 'dropout', 'rate' , opts.dropOutRatio) ;
% netA.layers = [netA.layers(1:15) drop1 netA.layers(16:17) drop2 netA.layers(18:end)] ;
% netB.layers = [netB.layers(1:15) drop1 netB.layers(16:17) drop2 netB.layers(18:end)] ;
% netA.layers=netA.layers(1:end-1);
% netB.layers=netB.layers(1:end-1);
% if ~isfield(netA, 'meta')
%   netA = vl_simplenn_tidy(netA);
%   netA = dagnn.DagNN.fromSimpleNN(netA,'canonicalNames', true) ;
%   netA = dagnn.DagNN.loadobj(netA);
%   netB = dagnn.DagNN.loadobj(netB);
%   netA = netA.saveobj() ;
% end
% if ~isfield(netB, 'meta'), 
%   netB = vl_simplenn_tidy(netB);
%   netB = dagnn.DagNN.fromSimpleNN(netB,'canonicalNames', true) ; 
%   netB = netB.saveobj() ;
% end

% f = find(strcmp({netA.layers(:).type}, 'dagnn.Loss'));
% netA.layers(f(1)-1).name = 'prediction';
% f = find(strcmp({netB.layers(:).type}, 'dagnn.Loss'));
% netB.layers(f(1)-1).name = 'prediction';


f = find(strcmp({netA.layers(:).type}, 'dagnn.Conv'));
netA.layers(f(end)).name = 'prediction';
f = find(strcmp({netB.layers(:).type}, 'dagnn.Conv'));
netB.layers(f(end)).name = 'prediction';          

             
% f = find(strcmp({netA.layers(:).type}, 'dagnn.Loss'));
% netA.layers(f(1)-1).name = 'prediction';
% f = find(strcmp({netB.layers(:).type}, 'dagnn.Loss'));
% netB.layers(f(1)-1).name = 'prediction';

fusionLayerA = []; fusionLayerB = [];
if ~isempty(opts.train.fusionLayer)
for i=1:numel(netA.layers)
 if isfield(netA.layers(i),'name') && any(strcmp(netA.layers(i).name,opts.train.fusionLayer(:,1)))
   fusionLayerA = [fusionLayerA i]; 
 end                
end
for i=1:numel(netB.layers)
 if  isfield(netB.layers(i),'name') && any(strcmp(netB.layers(i).name,opts.train.fusionLayer(:,2)))
   fusionLayerB = [fusionLayerB i]; 
 end                
end
end

netA.meta.normalization.averageImage = mean(mean(netA.meta.normalization.averageImage, 1), 2);
netB.meta.normalization.averageImage = mean(mean(netB.meta.normalization.averageImage, 1), 2);
netB.meta.normalization.averageImage = gather(cat(3,netB.meta.normalization.averageImage, netA.meta.normalization.averageImage));



% rename layers, params and vars
for x=1:numel(netA.layers)
  if isfield(netA.layers(x), 'name'), netA.layers(x).name = [netA.layers(x).name '_spatial'] ;  end
end
for x=1:numel(netB.layers)
  if isfield(netB.layers(x), 'name'), netB.layers(x).name = [netB.layers(x).name '_temporal']; end
end
netA =  dagnn.DagNN.loadobj(netA);
for i = 1:numel(netA.vars),  if~strcmp(netA.vars(i).name,'label'), netA.renameVar(netA.vars(i).name, [netA.vars(i).name '_spatial']); end; end; 
for i = 1:numel(netA.params),  netA.renameParam(netA.params(i).name, [netA.params(i).name '_spatial']); end; 
netB =  dagnn.DagNN.loadobj(netB);
for i = 1:numel(netB.vars), if~strcmp(netB.vars(i).name,'label'), netB.renameVar(netB.vars(i).name, [netB.vars(i).name '_temporal']); end;end; 
for i = 1:numel(netB.params),  netB.renameParam(netB.params(i).name, [netB.params(i).name '_temporal']); end; 

% inject conv fusion layer
if addConv3D & any(~cellfun(@isempty,(strfind(opts.train.fusionLayer, 'prediction'))))
  if strcmp(opts.train.fuseInto,'temporal')
    [ netB ] = insert_conv_layers( netB, fusionLayerB(end), 'initMethod', opts.initMethod );
  else
    [ netA ] = insert_conv_layers( netA, fusionLayerA(end), 'initMethod', opts.initMethod );
  end
end

if ~addConv3D && ~doSum &&~doMax
  if strcmp(opts.train.fuseInto,'temporal')
    [ netB ] = insert_conv_layers( netB, fusionLayerB, 'initMethod', opts.initMethod );
  else
    [ netA ] = insert_conv_layers( netA, fusionLayerA, 'initMethod', opts.initMethod );
  end
end

if opts.train.removeFuseFrom, 
  switch opts.train.fuseFrom
    case 'spatial'
      netA.layers = netA.layers(1:fusionLayerA(end)); netA.rebuild;
    case'temporal'
      netB.layers = netB.layers(1:fusionLayerB(end)); netB.rebuild;
  end
end

% merge nets
netA = netA.saveobj() ;
netB = netB.saveobj() ;
net.layers = [netA.layers netB.layers] ;
net.params =  [netA.params netB.params] ;     
net.meta = netB.meta;
net = dagnn.DagNN.loadobj(net);
clear netA netB;
net = dagnn.DagNN.setLrWd(net, 'convFiltersLRWD', [1 1], 'convBiasesLRWD', [2 0], ...
  'fusionFiltersLRWD', [1 1], 'fusionBiasesLRWD', [2 0], ...
  'filtersLRWD' , [1 1], 'biasesLRWD' , [2 0] ) ;


for i = 1:size(opts.train.fusionLayer,1)
  if strcmp(opts.train.fuseInto,'spatial')
    i_fusion = find(~cellfun('isempty', strfind({net.layers.name}, ...
      [opts.train.fusionLayer{i,1} '_' opts.train.fuseInto])));
  else
    i_fusion = find(~cellfun('isempty', strfind({net.layers.name}, ...
      [opts.train.fusionLayer{i,2} '_' opts.train.fuseInto])));
  end
  name_concat = [opts.train.fusionLayer{i,2} '_concat'];
 
  if doSum
    block = dagnn.Sum() ;
    net.addLayerAt(i_fusion(end), name_concat, block, ...
               [net.layers(strcmp({net.layers.name},[opts.train.fusionLayer{i,1} '_spatial'])).outputs ...
                net.layers(strcmp({net.layers.name},[opts.train.fusionLayer{i,2} '_temporal'])).outputs], ...
                name_concat) ;   
              

  elseif doMax
      block = dagnn.Max() ;
      net.addLayerAt(i_fusion(end), name_concat, block, ...
               [net.layers(strcmp({net.layers.name},[opts.train.fusionLayer{i,1} '_spatial'])).outputs ...
                net.layers(strcmp({net.layers.name},[opts.train.fusionLayer{i,2} '_temporal'])).outputs], ...
                name_concat) ;   
  else
    block = dagnn.Concat() ;
    net.addLayerAt(i_fusion(end), name_concat, block, ...
               [net.layers(strcmp({net.layers.name},[opts.train.fusionLayer{i,1} '_spatial'])).outputs ...
                net.layers(strcmp({net.layers.name},[opts.train.fusionLayer{i,2} '_temporal'])).outputs], ...
                name_concat) ;   
  end

  % set input for fusion layer
  net.layers(i_fusion(end)+2).inputs{1} = name_concat;
end

% set inputs
net.addVar('input_flow')
net.vars(net.getVarIndex('input_flow')).fanout = net.vars(net.getVarIndex('input_flow')).fanout + 1 ;
% i_conv1= find(~cellfun('isempty', strfind({net.layers.name},'conv1_1_temporal')));
i_conv1= find(~cellfun('isempty', strfind({net.layers.name},'conv1_spatial_temporal')));
net.layers(i_conv1(1)).inputs = {'input_flow'};
net.renameVar(net.vars(1).name, 'input');

if addConv3D
  block = dagnn.Conv3D() ;
  params(1).name = 'conv3Df' ;
  in = 4096 ;
%   in = size(net.params(net.getParamIndex('conv5_3f_spatial')).value,4) + ...
%     size(net.params(net.getParamIndex('conv5_3f_temporal')).value,4) ;
  out = 2048;

  kernel = eye(in/2,out,'single');
  kernel = cat(1, .25 * kernel, .75 * kernel);
  kernel = permute(kernel, [4 5 3 1 2]);

  sigma = 1;
  [X,Y,Z] = ndgrid(-1:1, -1:1, -1:1);
  G3 = exp( -((X.*X)/(sigma*sigma) + (Y.*Y)/(sigma*sigma) + (Z.*Z)/(sigma*sigma))/2 );
  G3 = G3./sum(G3(:));
  kernel = bsxfun(@times, kernel, G3);

  params(1).value = kernel;
  params(2).name = 'conv3Db' ;
  params(2).value = zeros(1, out ,'single') ;

  pads = size(kernel); pads = ceil(pads(1:3) / 2) - 1;
  block.pad = [pads(1),pads(1), pads(2),pads(2), pads(3),pads(3)]; 
  block.stride = [1 1 1]; 
  block.size = size(kernel);

  i_relu5 = find(~cellfun('isempty', strfind({net.layers.name},name_concat)));
%   i_relu5 = find(~cellfun('isempty', strfind({net.layers.name},'relu5_3_concat')));
  net.addLayerAt(i_relu5, 'conv53D',  block, ...
               [net.layers(i_relu5).outputs ], ...
                'conv3D5', {params.name}) ;  

  net.params(net.getParamIndex(params(1).name)).value = params(1).value ;
  net.params(net.getParamIndex(params(2).name)).value = params(2).value ;
%   net.params(net.getParamIndex(params(1).name)).learningRate = 1;
  net.params(net.getParamIndex(params(2).name)).learningRate = 2;
  net.params(net.getParamIndex(params(2).name)).weightDecay = 0;

  block = dagnn.ReLU() ;
  net.addLayerAt(i_relu5+1, 'relu3D5',  block, ...
               [net.layers(i_relu5+1).outputs ], ...
                'relu3D5') ;

  pool5_layer = find(~cellfun('isempty', strfind({net.layers.name},['pool5_' opts.train.fuseInto])));
  net.layers(pool5_layer(1)).inputs = {'relu3D5'};
end
if addPool3D
  block = dagnn.AvePooling3D() ;
  block.method = 'avg' ;

  i_pool5 = find(~cellfun('isempty', strfind({net.layers.name},['pool5_spatial_' opts.train.fuseInto])));
  i_pool5 = (i_pool5(1));
  block.poolSize = [1 1 nFrames];         
  block.pad = [net.layers(i_pool5).block.pad 0,0]; 
  block.stride = [net.layers(i_pool5).block.stride 2];     
  net.addLayerAt(i_pool5, ['pool3D5_' opts.train.fuseInto], block, ...
               [net.layers(i_pool5).inputs], ...
                 [net.layers(i_pool5).outputs]) ; 
  net.removeLayer(['pool5_spatial_' opts.train.fuseInto], 0) ;    
%   net.layers(i_pool5).inputs=net.layers(i_pool5+1).outputs;
%   net.layers(i_pool5).inputIndexes=net.layers(i_pool5+1).outputIndexes;
  
  i_pool5 = find(~cellfun('isempty', strfind({net.layers.name},['pool5_spatial_' opts.train.fuseFrom ])));                 
  if ~isempty(i_pool5)
      i_pool5=i_pool5(1);
    block = dagnn.AvePooling3D() ;

    block.poolSize = [1 1 nFrames];
    block.pad = [net.layers(i_pool5).block.pad 0,0];
    block.stride = [net.layers(i_pool5).block.stride 2];

    net.addLayerAt(i_pool5, ['pool3D5_' opts.train.fuseFrom], block, ...
                 [net.layers(i_pool5).inputs], ...
                   [net.layers(i_pool5).outputs]) ;      
%     net.layers(i_pool5).inputs=net.layers(i_pool5+1).outputs;
%   net.layers(i_pool5).inputIndexes=net.layers(i_pool5+1).outputIndexes;
    net.removeLayer(['pool5_spatial_' opts.train.fuseFrom ], 0) ;    
  end

end

if addConv3D || addPool3D
opts.train.augmentation = 'noCtr';

opts.train.frameSample = 'temporalStrideRandom';
opts.train.nFramesPerVid = nFrames * 1;
opts.train.temporalStride = 5:15; 

opts.train.valmode = 'temporalStrideRandom';
opts.train.numValFrames = nFrames * 1 ;
opts.train.saveAllPredScores = 0 ;
opts.train.denseEval = 1;
end  
 
net.meta.normalization.rgbVariance = [];

opts.train.train = find(ismember(imdb.images.set, [1])) ;
opts.train.train = repmat(opts.train.train,1,opts.train.epochFactor);

% opts.train.backpropDepth = ['res5c_relu_spatial_temporal';'res5c_relu_spatial_temporal';'res5c_relu_spatial_temporal';'res5c_relu_spatial_temporal';'res5c_relu_spatial_temporal';];
 opts.train.backpropDepth = ['res5c_relu_temporal';'res5c_relu_temporal';'res3d_relu_temporal';'res3d_relu_temporal';'res3d_relu_temporal';'res3d_relu_temporal';'conv1_relu_temporal'];%'relu3_temporal';'relu3_temporal';
% opts.train.backpropDepth = ['relu5_spatial';'relu5_spatial';'relu3_spatial';'relu3_spatial';'relu1_spatial';'relu1_spatial'];
 opts.train.backpropDepth = cellstr(opts.train.backpropDepth);

 for l = 1:numel(net.layers)
  if isa(net.layers(l).block, 'dagnn.DropOut')
    net.layers(l).block.rate = opts.dropOutRatio;
  end
end


%get ride of dropout layers
% for l = 1:numel(net.layers)
%   if isa(net.layers(l).block, 'dagnn.DropOut')
% %     net.layers(l).block.rate = opts.dropOutRatio;
%       net.layers(l-1).inputs=net.layers(l).inputs;
%       net.layers(l-1).inputIndexes=net.layers(l).inputIndexes;
%       %net.removeLayer(net.layers(l).name,0);
% 
%   end
% end


net.layers(~cellfun('isempty', strfind({net.layers(:).name}, 'err'))) = [] ;
% net.layers(~cellfun('isempty', strfind({net.layers(:).name}, 'drop'))) = [] ;
net.rebuild() ;


opts.train.derOutputs = {} ;
for l=1:numel(net.layers)
  if isa(net.layers(l).block, 'dagnn.Loss') && isempty(strfind(net.layers(l).block.loss, 'err'))
    if opts.backpropFuseFrom || ~isempty(strfind(net.layers(l).name, opts.train.fuseInto ))
      fprintf('setting derivative for layer %s \n', net.layers(l).name);
      opts.train.derOutputs = [opts.train.derOutputs, net.layers(l).outputs, {1}] ;
    end
     net.addLayer(['err1_' net.layers(l).name(end-7:end) ], dagnn.Loss('loss', 'classerror'), ...
             net.layers(l).inputs, 'error') ;
  end
end

net.print('MaxNumColumns', 5, 'Layers','*','variables','') ;   

net.conserveMemory = 1 ;
fn = getBatchWrapper_ucf101_rgbflow(net.meta.normalization, opts.numFetchThreads, opts.train) ;

[info] = cnn_train_dag(net, imdb, fn, opts.train) ;



