function script_rpn_bf_pedestrian_VGG16_scut()

clc;
clear mex;
clear is_valid_handle; % to clear init_key
run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'startup'));
%% -------------------- CONFIG --------------------
opts.caffe_version          = 'caffe_faster_rcnn';
opts.gpu_id                 = 2;
active_caffe_mex(opts.gpu_id, opts.caffe_version);

exp_name = 'VGG16_scut';

% do validation, or not 
opts.do_val                 = true; 
% model
model                       = Model.VGG16_for_rpn_pedestrian('VGG16_caltech');
% cache base
cache_base_proposal         = 'vgg16_skip02_overall'; % ouput/exp_name/rpn_cachedir/cache_base_proposal
% train/test data
dataset                     = [];
use_flipped                 = false;
dataset                     = Dataset.scut_trainval(dataset, 'train02',use_flipped);
dataset                     = Dataset.scut_test(dataset, 'test25',false);

% %% -------------------- TRAIN --------------------
% conf
conf_proposal               = proposal_config(model);
% set cache folder for each stage
model                       = Faster_RCNN_Train.set_cache_folder_rpn(cache_base_proposal, model);
% generate anchors and pre-calculate output size of rpn network 

conf_proposal.exp_name = exp_name;
[conf_proposal.anchors, conf_proposal.output_width_map, conf_proposal.output_height_map] ...
                            = proposal_prepare_anchors(conf_proposal, model.stage1_rpn.cache_name, model.stage1_rpn.test_net_def_file);



%% read the RPN model
imdbs_name = cell2mat(cellfun(@(x) x.name, dataset.imdb_train, 'UniformOutput', false));
log_dir = fullfile(pwd, 'output', exp_name, 'rpn_cachedir', model.stage1_rpn.cache_name, imdbs_name);
final_model_path = fullfile(log_dir, 'final');
if exist(final_model_path, 'file')
    model.stage1_rpn.output_model_file = final_model_path;
else
    error('RPN model does not exist.');
end
            
%% generate proposal for training the BF
model.stage1_rpn.nms.per_nms_topN = -1;
model.stage1_rpn.nms.nms_overlap_thres = 1;
model.stage1_rpn.nms.after_nms_topN = 40;
roidb_test_BF = Faster_RCNN_Train.do_generate_bf_proposal_pd(conf_proposal, model.stage1_rpn, dataset.imdb_test, dataset.roidb_test);
model.stage1_rpn.nms.nms_overlap_thres = 0.7;
model.stage1_rpn.nms.after_nms_topN = 1000;
roidb_train_BF = Faster_RCNN_Train.do_generate_bf_proposal_pd(conf_proposal, model.stage1_rpn, dataset.imdb_train{1}, dataset.roidb_train{1});

%% train the BF
BF_cachedir = fullfile(pwd, 'output', exp_name, 'bf_cachedir');
mkdir_if_missing(BF_cachedir);
dataDir='datasets/scut/';
posGtDir=[dataDir 'train02' '/annotations'];
addpath('external/code3.2.1');
addpath(genpath('external/toolbox'));
BF_prototxt_path = fullfile('models', 'VGG16_caltech', 'bf_prototxts', 'test_feat_conv34atrous_v2.prototxt');
conf.image_means = model.mean_image;
conf.test_scales = conf_proposal.test_scales;
conf.test_max_size = conf_proposal.max_size;
if ischar(conf.image_means)
    s = load(conf.image_means);
    s_fieldnames = fieldnames(s);
    assert(length(s_fieldnames) == 1);
    conf.image_means = s.(s_fieldnames{1});
end
log_dir = fullfile(BF_cachedir, 'log');
mkdir_if_missing(log_dir);
caffe_log_file_base = fullfile(log_dir, 'caffe_log');
caffe.init_log(caffe_log_file_base);
caffe_net = caffe.Net(BF_prototxt_path, 'test');
caffe_net.copy_from(final_model_path);
caffe.set_mode_gpu();

% set up opts for training detector (see acfTrain)
opts=BF.do_train_bf(); 
opts.cache_dir = BF_cachedir;
opts.name=fullfile(opts.cache_dir, 'DeepCaltech_otf');
opts.nWeak=[64 128 256 512 1024 1536 2048];
opts.bg_hard_min_ratio = [1 1 1 1 1 1 1];
opts.pBoost.pTree.maxDepth=5; 
opts.pBoost.discrete=0;
opts.pBoost.pTree.fracFtrs=1/4; 
opts.first_nNeg = 30000;
opts.nNeg=5000; opts.nAccNeg=50000;
pLoad={'lbls',{'walk_person','ride_person'},'ilbls',{'people','person?','people?','squat_person'},'squarify',{3,.46}};
opts.pLoad = [pLoad 'hRng',[20 inf], 'vType', {'none'}];
opts.roidb_train = roidb_train_BF;
opts.roidb_test = roidb_test_BF;
opts.imdb_train = dataset.imdb_train{1};
opts.imdb_test = dataset.imdb_test;
opts.fg_thres_hi = 1;
opts.fg_thres_lo = 0.8; %[lo, hi)
opts.bg_thres_hi = 0.5;
opts.bg_thres_lo = 0; %[lo hi)
opts.dataDir = dataDir;
opts.caffe_net = caffe_net;
opts.conf = conf;
opts.exp_name = exp_name;
opts.fg_nms_thres = 1;
opts.fg_use_gt = true;
opts.bg_nms_thres = 1;
opts.max_rois_num_in_gpu = 3000;
opts.init_detector = '';
opts.load_gt = false;
opts.ratio = 1.0;
opts.nms_thres = 0.5;

% forward an image to check error and get the feature length
img = imread(dataset.imdb_test.image_at(16));
tic;
tmp_box = roidb_test_BF.rois(16).boxes;
retain_num = round(size(tmp_box, 1) * opts.bg_hard_min_ratio(end));
retain_idx = randperm(size(tmp_box, 1), retain_num);
sel_idx = true(size(tmp_box, 1), 1);
sel_idx = sel_idx(retain_idx);
if opts.bg_nms_thres < 1
    sel_box = roidb_test_BF.rois(1).boxes(sel_idx, :);
    sel_scores = roidb_test_BF.rois(1).scores(sel_idx, :);
    nms_sel_idxes = nms([sel_box sel_scores], opts.bg_nms_thres);
    sel_idx = sel_idx(nms_sel_idxes);
end
tmp_box = roidb_test_BF.rois(16).boxes(sel_idx, :);
feat = rois_get_features_ratio(conf, caffe_net, img, tmp_box, opts.max_rois_num_in_gpu, opts.ratio);
toc;
opts.feat_len = length(feat);

fs=bbGt('getFiles',{posGtDir});
train_gts = cell(length(fs), 1);
for i = 1:length(fs)
    [~,train_gts{i}]=bbGt('bbLoad',fs{i},opts.pLoad);
end
opts.train_gts = train_gts;

% train BF detector
detector = BF.do_train_bf( opts );

% visual
if 0 % set to 1 for visual
  rois = opts.roidb_test.rois;
  imgNms=bbGt('getFiles',{[dataDir 'test/images']});
  for i = 1:length(rois)
      if ~isempty(rois(i).boxes)
          img = imread(dataset.imdb_test.image_at(i));  
          feat = rois_get_features_ratio(conf, caffe_net, img, rois(i).boxes, opts.max_rois_num_in_gpu, opts.ratio);   
          scores = adaBoostApply(feat, detector.clf);
          bbs = [rois(i).boxes scores];
          % do nms
          sel_idx = nms(bbs, opts.nms_thres);
          sel_idx = intersect(sel_idx, find(~rois(i).gt)); % exclude gt
          sel_idx = intersect(sel_idx, find(bbs(:, end) > opts.cascThr));
          bbs = bbs(sel_idx, :);
          bbs(:, 3) = bbs(:, 3) - bbs(:, 1);
          bbs(:, 4) = bbs(:, 4) - bbs(:, 2);
          if ~isempty(bbs)
              I=imread(imgNms{i});
              figure(1); im(I); bbApply('draw',bbs); pause();
          end
      end
  end
end

% test detector and plot roc
method_name = 'RPN+BF-skip02-overall';
folder1 = fullfile(pwd, 'output', exp_name, 'bf_cachedir', method_name);
folder2 = fullfile(pwd, 'external', 'code3.2.1', 'data-scut', 'res', method_name);

if ~exist(folder1, 'dir')
    [~,~,gt,dt]=BF.do_test_bf('name',opts.name,'roidb_test', opts.roidb_test, 'imdb_test', opts.imdb_test, ...
        'gtDir',[dataDir 'test25/annotations'],'pLoad',[pLoad, 'hRng',[50 inf],...
        'xRng',[10 700],'yRng',[10 570]],...
        'reapply',1,'show',2, 'nms_thres', opts.nms_thres, ...
        'conf', opts.conf, 'caffe_net', opts.caffe_net, 'silent', false, 'cache_dir', opts.cache_dir, 'ratio', opts.ratio,'method_name',method_name);
end

copyfile(folder1, folder2);
tmp_dir = pwd;
cd(fullfile(pwd, 'external', 'code3.2.1'));
dbEval_scut;
cd(tmp_dir);

caffe.reset_all();
end

function [anchors, output_width_map, output_height_map] = proposal_prepare_anchors(conf, cache_name, test_net_def_file)
    [output_width_map, output_height_map] ...                           
                                = proposal_calc_output_size_pd(conf, test_net_def_file);
    anchors                = proposal_generate_anchors_pd(cache_name, ...
                                    'scales', 2.6*(1.3.^(0:8)), ...
                                    'ratios', [1 / 0.46], ...
                                    'exp_name', conf.exp_name);
end

function conf = proposal_config(model)
    conf = proposal_config_pd('image_means', model.mean_image,...
                              'feat_stride', model.feat_stride ...
                             ,'scales',        576   ...
                             ,'max_size',      720   ...
                             ,'ims_per_batch', 1     ...
                             ,'batch_size',    120   ...
                             ,'fg_fraction',   1/6   ...
                             ,'bg_weight',     1.0   ...
                             ,'fg_thresh',     0.5   ...
                             ,'bg_thresh_hi',  0.5   ...
                             ,'bg_thresh_lo',  0     ...
                             ,'test_scales',   576   ...
                             ,'test_max_size', 720   ...
                             ,'test_nms',      0.5   ...
                             ,'test_min_box_size',0  ...
                             ,'test_min_box_height',20 ...
                             ,'datasets',     'scut' ...
                              );
    % for eval_pLoad
    pLoad={'lbls',{'walk_person','ride_person'},'ilbls',{'people','person?',...
       'people?','squat_person'},'squarify',{3,.46}};
    pLoad = [pLoad 'hRng',[50 inf], 'vType',{{'none','partial'}},'xRng',[10 700],'yRng',[10 570]];
    conf.eval_pLoad = pLoad;
end