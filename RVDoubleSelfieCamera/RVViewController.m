//
//  RVViewController.m
//  RVDoubleSelfieCamera
//
//  Created by Виталий Рыжов on 27.02.17.
//  Copyright © 2017 VitaliyRyzhov. All rights reserved.
//

#import "RVViewController.h"

@import AVFoundation;
@import GLKit;

#pragma mark - GLKView

@interface GLKViewWithBounds : GLKView

@property (nonatomic, assign) CGRect viewBounds;

@end


@implementation GLKViewWithBounds

@end


#pragma mark - View Controller

@interface RVViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong) CIContext *ciContext;
@property (nonatomic, strong) EAGLContext *eaglContext;

@property (nonatomic, strong) AVCaptureSession *captureSession;

@property (nonatomic, strong) dispatch_queue_t captureSessionQueue;

@property (nonatomic, assign) CMVideoDimensions currentVideoDimensions;

@property (nonatomic, strong) NSMutableArray *feedViews;

@end


@implementation RVViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.edgesForExtendedLayout = UIRectEdgeNone;
    self.view.backgroundColor = [UIColor blackColor];
    self.title = @"OpenGL";
    
    self.feedViews = [NSMutableArray array];
    
    if ([[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count] > 0) {
        _captureSessionQueue = dispatch_queue_create("capture_session_queue", NULL);
        
        [self setupContexts];
        
        // Sessions
        [self setupSession];
        
        // Feed Views
        [self setupFeedViews];
    }
}


#pragma mark - Feed Views

- (void)setupFeedViews {
    NSUInteger numberOfFeeds = 2;
    
    CGFloat feedViewHeight = (self.view.bounds.size.height)/numberOfFeeds;
    
    for (NSUInteger i = 0; i < numberOfFeeds; i++) {
        GLKViewWithBounds *feedView = [self setupFeedViewWithFrame:CGRectMake(0.0, feedViewHeight*i, self.view.bounds.size.width, feedViewHeight)];
        [self.view addSubview:feedView];
        [self.feedViews addObject:feedView];
    }
}


- (GLKViewWithBounds *)setupFeedViewWithFrame:(CGRect)frame {
    GLKViewWithBounds *feedView = [[GLKViewWithBounds alloc] initWithFrame:frame context:self.eaglContext];
    
    feedView.enableSetNeedsDisplay = NO;
    feedView.transform = CGAffineTransformMakeRotation(M_PI_2);
    feedView.frame = frame;
    
    [feedView bindDrawable];
    
    feedView.viewBounds = CGRectMake(0.0, 0.0, feedView.drawableWidth, feedView.drawableHeight);
    
    return feedView;
}


#pragma mark - Contexts and Sessions

- (void)setupContexts {
    _eaglContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    
    _ciContext = [CIContext contextWithEAGLContext:_eaglContext
                                           options:@{kCIContextWorkingColorSpace : [NSNull null]} ];
}


- (void)setupSession {
    if (_captureSession)
        return;
    
    dispatch_async(_captureSessionQueue, ^(void) {
        NSError *error = nil;
        
        // get the input device and also validate the settings
        NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        
        AVCaptureDevice *_videoDevice = nil;
        
        AVCaptureDevicePosition position = AVCaptureDevicePositionFront;
        
        for (AVCaptureDevice *device in videoDevices)
        {
            if (device.position == position) {
                _videoDevice = device;
                break;
            }
        }
        if (!_videoDevice) {
            _videoDevice = [videoDevices objectAtIndex:0];
        }
        
        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:_videoDevice error:&error];
        if (!videoDeviceInput)
        {
            [self _showAlertViewWithMessage:[NSString stringWithFormat:@"Unable to obtain video device input, error: %@", error]];
            return;
        }
        
        NSString *preset = AVCaptureSessionPresetMedium;
        
        if (![_videoDevice supportsAVCaptureSessionPreset:preset])
        {
            [self _showAlertViewWithMessage:[NSString stringWithFormat:@"Capture session preset not supported by video device: %@", preset]];
            return;
        }
        
        NSDictionary *outputSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInteger:kCVPixelFormatType_32BGRA]};
        
        _captureSession = [[AVCaptureSession alloc] init];
        _captureSession.sessionPreset = preset;
        
        
        AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        videoDataOutput.videoSettings = outputSettings;
        [videoDataOutput setSampleBufferDelegate:self queue:_captureSessionQueue];
        
        [_captureSession beginConfiguration];
        
        if (![_captureSession canAddOutput:videoDataOutput])
        {
            [self _showAlertViewWithMessage:@"Cannot add video data output"];
            _captureSession = nil;
            return;
        }
        
        [_captureSession addInput:videoDeviceInput];
        [_captureSession addOutput:videoDataOutput];
        
        [_captureSession commitConfiguration];
        
        [_captureSession startRunning];
    });
}


#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    
    _currentVideoDimensions = CMVideoFormatDescriptionGetDimensions(formatDesc);
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:(CVPixelBufferRef)imageBuffer options:nil];
    CGRect sourceExtent = sourceImage.extent;
    CIFilter * noirFilter = [CIFilter filterWithName:@"CIPhotoEffectNoir" keysAndValues: kCIInputImageKey,sourceImage, nil];
    CIImage *filteredImage = [noirFilter outputImage];
    CGFloat sourceAspect = sourceExtent.size.width / sourceExtent.size.height;
    
    GLKViewWithBounds *feedViewTop = [self.feedViews firstObject];
    GLKViewWithBounds *feedViewDown = [self.feedViews lastObject];
    
    if (feedViewTop) {
        
        CGFloat previewAspect = feedViewTop.viewBounds.size.width  / feedViewTop.viewBounds.size.height;
        
        CGRect drawRect = sourceExtent;
        if (sourceAspect > previewAspect) {
            drawRect.origin.x += (drawRect.size.width - drawRect.size.height * previewAspect) / 2.0;
            drawRect.size.width = drawRect.size.height * previewAspect;
        } else {
            drawRect.origin.y += (drawRect.size.height - drawRect.size.width / previewAspect) / 2.0;
            drawRect.size.height = drawRect.size.width / previewAspect;
        }
        
        [feedViewTop bindDrawable];
        
        
        if (feedViewTop) {
            [_ciContext drawImage:sourceImage inRect:feedViewTop.viewBounds fromRect:drawRect];
            
        }
        
        [feedViewTop display];
    }
    if (feedViewDown){
        
        CGFloat previewAspect = feedViewDown.viewBounds.size.width  / feedViewDown.viewBounds.size.height;
        CGRect drawRect = sourceExtent;
        if (sourceAspect > previewAspect) {
            drawRect.origin.x += (drawRect.size.width - drawRect.size.height * previewAspect) / 2.0;
            drawRect.size.width = drawRect.size.height * previewAspect;
        } else {
            drawRect.origin.y += (drawRect.size.height - drawRect.size.width / previewAspect) / 2.0;
            drawRect.size.height = drawRect.size.width / previewAspect;
        }
        
        [feedViewDown bindDrawable];
        
        
        if (feedViewDown) {
            [_ciContext drawImage:filteredImage inRect:feedViewDown.viewBounds fromRect:drawRect];
        }
        
        [feedViewDown display];
    }
}

#pragma mark - Misc

- (void)_showAlertViewWithMessage:(NSString *)message {
    [self _showAlertViewWithMessage:message title:@"Error"];
}


- (void)_showAlertViewWithMessage:(NSString *)message title:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                        message:message
                                                       delegate:nil
                                              cancelButtonTitle:@"Dismiss"
                                              otherButtonTitles:nil];
        [alert show];
    });
}

@end
