function model = VGG16_for_Fast_RCNN_conv5_hole(exp_name,model)
% VGG 16layers (only finetuned from conv3_1)

nms.train_proposal.per_nms_topN   = -1;
nms.train_proposal.nms_overlap_thres  = 0.7;
nms.train_proposal.after_nms_topN = 1000;

nms.test_proposal.per_nms_topN   = 6000;
nms.test_proposal.nms_overlap_thres  = 0.7;
nms.test_proposal.after_nms_topN = 300;

nms.test.per_nms_topN   = 10000;
nms.test.nms_overlap_thres  = 0.5;
nms.test.after_nms_topN = 40;


model.mean_image                                = fullfile(pwd, 'models', 'Faster', 'pre_trained_models', 'vgg_16layers', 'mean_image');
model.pre_trained_net_file                      = fullfile(pwd, 'models', 'Faster', 'pre_trained_models', 'vgg_16layers', 'vgg16.caffemodel');
% Stride in input image pixels at the last conv layer
model.feat_stride                               = 16;

%% stage 1 rpn, inited from pre-trained network
model.stage1_rpn.solver_def_file                = fullfile(pwd, 'models', exp_name, 'rpn_prototxts', 'vgg_16layers_conv3_1', 'solver_60k80k.prototxt');
model.stage1_rpn.test_net_def_file              = fullfile(pwd, 'models', exp_name, 'rpn_prototxts', 'vgg_16layers_conv3_1', 'test.prototxt');
model.stage1_rpn.init_net_file                  = model.pre_trained_net_file;

% rpn train proposal setting
model.stage1_rpn.nms                            = nms.train_proposal;

%% stage 1 fast rcnn, inited from pre-trained network
model.stage1_fast_rcnn.solver_def_file          = fullfile(pwd, 'models', exp_name, 'fast_rcnn_prototxts', 'vgg_16layers_conv5_3hole', 'solver_30k40k.prototxt');
model.stage1_fast_rcnn.test_net_def_file        = fullfile(pwd, 'models', exp_name, 'fast_rcnn_prototxts', 'vgg_16layers_conv5_3hole', 'test.prototxt');
model.stage1_fast_rcnn.init_net_file            = model.pre_trained_net_file;

% fast test setting
model.stage1_fast_rcnn.nms                      = nms.test;

model.nms = nms;
end