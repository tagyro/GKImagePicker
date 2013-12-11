//
//  GKImageCropView.m
//  GKImagePicker
//
//  Created by Georg Kitz on 6/1/12.
//  Copyright (c) 2012 Aurora Apps. All rights reserved.
//

#import "GKImageCropView.h"
#import "GKImageCropOverlayView.h"
#import "GKResizeableCropOverlayView.h"
#import "UIImage+ImageOrientation.h"
#import <QuartzCore/QuartzCore.h>

#define rad(angle) ((angle) / 180.0 * M_PI)

static CGRect GKScaleRect(CGRect rect, CGFloat scale)
{
    return CGRectMake(rect.origin.x * scale, rect.origin.y * scale, rect.size.width * scale, rect.size.height * scale);
}

@interface ScrollView : UIScrollView
@end

@implementation ScrollView

- (void)layoutSubviews{
    [super layoutSubviews];
    
    UIView *zoomView = [self.delegate viewForZoomingInScrollView:self];
    
    CGSize boundsSize = self.bounds.size;
    CGRect frameToCenter = zoomView.frame;
    
    // center horizontally
    if (frameToCenter.size.width < boundsSize.width)
        frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2;
    else
        frameToCenter.origin.x = 0;
    
    // center vertically
    if (frameToCenter.size.height < boundsSize.height)
        frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2;
    else
        frameToCenter.origin.y = 0;
    
    zoomView.frame = frameToCenter;
}

@end

@interface GKImageCropView ()<UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) GKImageCropOverlayView *cropOverlayView;
@property (nonatomic, assign) CGFloat xOffset;
@property (nonatomic, assign) CGFloat yOffset;

- (CGRect)_calcVisibleRectForResizeableCropArea;
- (CGRect)_calcVisibleRectForCropArea;
- (CGAffineTransform)_orientationTransformedRectOfImage:(UIImage *)image;
@end

@implementation GKImageCropView

#pragma mark -
#pragma Getter/Setter

@synthesize scrollView, imageView, cropOverlayView, resizableCropArea, xOffset, yOffset;

- (void)setImageToCrop:(UIImage *)imageToCrop{
    self.imageView.image = imageToCrop;
}

- (UIImage *)imageToCrop{
    return self.imageView.image;
}

- (void)setCropSize:(CGSize)cropSize{
    
    if (self.cropOverlayView == nil){
        if(self.resizableCropArea)
            self.cropOverlayView = [[GKResizeableCropOverlayView alloc] initWithFrame:self.bounds andInitialContentSize:CGSizeMake(cropSize.width, cropSize.height)];
        else
            self.cropOverlayView = [[GKImageCropOverlayView alloc] initWithFrame:self.bounds];
        
        [self addSubview:self.cropOverlayView];
    }
    self.cropOverlayView.cropSize = cropSize;
}

- (CGSize)cropSize{
    return self.cropOverlayView.cropSize;
}

#pragma mark -
#pragma Public Methods

- (UIImage *)croppedImage{
    
    UIImage *fixedOrientation = [self.imageToCrop fixOrientation];
    //  save original picture and the new version with a fixed orientation in the Document's app directory
//    [FRSHelper saveInDocumentsImage:self.imageToCrop withName:@"imageToCrop"];
//    [FRSHelper saveInDocumentsImage:fixedOrientation withName:@"fixedOrientationImage"];
    
    //Calculate rect that needs to be cropped
    CGRect visibleRect = self.resizableCropArea ? [self _calcVisibleRectForResizeableCropArea] : [self _calcVisibleRectForCropArea];
    
    //transform visible rect to image orientation
    CGAffineTransform rectTransform = [self _orientationTransformedRectOfImage:fixedOrientation];
    visibleRect = CGRectApplyAffineTransform(visibleRect, rectTransform);
    
    //finally crop image
    CGImageRef imageRef = CGImageCreateWithImageInRect([fixedOrientation CGImage], visibleRect);
    UIImage *result = [UIImage imageWithCGImage:imageRef scale:fixedOrientation.scale orientation:fixedOrientation.imageOrientation];
    CGImageRelease(imageRef);
    //  save the result image after cropping in the Document's app directory
//    [FRSHelper saveInDocumentsImage:result withName:@"result"];
    
    return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                  Original version - not used anymore since we crop the image with a different approach
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//- (UIImage *)croppedImage {
//
//    //Calculate rect that needs to be cropped
//    CGRect visibleRect = self.resizableCropArea ? [self _calcVisibleRectForResizeableCropArea] : [self _calcVisibleRectForCropArea];
//
//    //transform visible rect to image orientation
//    CGAffineTransform rectTransform = [self _orientationTransformedRectOfImage:self.imageToCrop];
//    visibleRect = CGRectApplyAffineTransform(visibleRect, rectTransform);
//
//    //finally crop image
//    CGImageRef imageRef = CGImageCreateWithImageInRect([self.imageToCrop CGImage], visibleRect);
//    UIImage *result = [UIImage imageWithCGImage:imageRef scale:self.imageToCrop.scale orientation:self.imageToCrop.imageOrientation];
//    CGImageRelease(imageRef);
//    return result;
//}
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (CGFloat)getAspectRatio {
    UIImage *fixedOrientation = [self.imageToCrop fixOrientation];
    
    CGFloat width = self.imageView.frame.size.width;
    CGFloat height = self.imageView.frame.size.height;
    CGFloat aspectRatio = width / height;
    
    if (width < height) {
        width = height * aspectRatio;
        if (width > fixedOrientation.size.width) {
            width = fixedOrientation.size.width;
            height = width * aspectRatio;
        }
    } else {
        height = width * aspectRatio;
        if (height > fixedOrientation.size.height) {
            height = fixedOrientation.size.height;
            width = height * aspectRatio;
        }
    }
    return width / height;
}

- (CGSize)getProportionalAspectRatioSize {
    UIImage *fixedOrientation = [self.imageToCrop fixOrientation];
    CGSize originalImageSize = fixedOrientation.size;
    CGFloat aspectRatio = [self getAspectRatio];
    CGSize proportionalAspectRatioSize = CGSizeMake(originalImageSize.height*aspectRatio, originalImageSize.width/aspectRatio);
    return proportionalAspectRatioSize;
}


- (CGRect)_calcVisibleRectForResizeableCropArea{
    UIImage *fixedOrientation = [self.imageToCrop fixOrientation];
    
    GKResizeableCropOverlayView* resizeableView = (GKResizeableCropOverlayView*)self.cropOverlayView;
    
    //first of all, get the size scale by taking a look at the real image dimensions. Here it doesn't matter if you take
    //the width or the hight of the image, because it will always be scaled in the exact same proportion of the real image
    CGFloat sizeScale = fixedOrientation.size.width / self.imageView.frame.size.width;
    sizeScale *= self.scrollView.zoomScale;
    
    //then get the postion of the cropping rect inside the image
    CGRect visibleRect = [resizeableView.contentView convertRect:resizeableView.contentView.bounds toView:imageView];
    return visibleRect = GKScaleRect(visibleRect, sizeScale);
}

-(CGRect)_calcVisibleRectForCropArea{
    
    UIImage *fixedOrientation = [self.imageToCrop fixOrientation];
    
    //scaled width/height in regards of real width to crop width
    CGFloat scaleWidth = fixedOrientation.size.width / self.cropSize.width;
    CGFloat scaleHeight = fixedOrientation.size.height / self.cropSize.height;
    CGFloat scale = MAX(scaleWidth, scaleHeight);
    
    //extract visible rect from scrollview and scale it
    CGRect visibleRect = [scrollView convertRect:scrollView.bounds toView:imageView];
    return visibleRect = GKScaleRect(visibleRect, scale);
}


- (CGAffineTransform)_orientationTransformedRectOfImage:(UIImage *)img
{
    CGAffineTransform rectTransform;
    switch (img.imageOrientation)
    {
        case UIImageOrientationLeft:
            rectTransform = CGAffineTransformTranslate(CGAffineTransformMakeRotation(rad(90)), 0, -img.size.height);
            break;
        case UIImageOrientationRight:
            rectTransform = CGAffineTransformTranslate(CGAffineTransformMakeRotation(rad(-90)), -img.size.width, 0);
            break;
        case UIImageOrientationDown:
            rectTransform = CGAffineTransformTranslate(CGAffineTransformMakeRotation(rad(-180)), -img.size.width, -img.size.height);
            break;
        default:
            rectTransform = CGAffineTransformIdentity;
    };
    
    return CGAffineTransformScale(rectTransform, img.scale, img.scale);
}

#pragma mark -
#pragma Override Methods

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor blackColor];
        self.scrollView = [[ScrollView alloc] initWithFrame:self.bounds ];
        self.scrollView.showsHorizontalScrollIndicator = NO;
        self.scrollView.showsVerticalScrollIndicator = NO;
        self.scrollView.delegate = self;
        self.scrollView.clipsToBounds = NO;
        self.scrollView.decelerationRate = 0.0;
        self.scrollView.backgroundColor = [UIColor clearColor];
        [self addSubview:self.scrollView];
        
        self.imageView = [[UIImageView alloc] initWithFrame:self.scrollView.frame];
        self.imageView.contentMode = UIViewContentModeScaleAspectFit;
        self.imageView.backgroundColor = [UIColor blackColor];
        [self.scrollView addSubview:self.imageView];
        
        
        self.scrollView.minimumZoomScale = CGRectGetWidth(self.scrollView.frame) / CGRectGetWidth(self.imageView.frame);
        self.scrollView.maximumZoomScale = 20.0;
        [self.scrollView setZoomScale:1.0];
    }
    return self;
}


- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event{
    if (!self.resizableCropArea)
        return self.scrollView;
    
    GKResizeableCropOverlayView* resizeableCropView = (GKResizeableCropOverlayView*)self.cropOverlayView;
    
    CGRect outerFrame = CGRectInset(resizeableCropView.cropBorderView.frame, -10 , -10);
    if (CGRectContainsPoint(outerFrame, point)){
        
        if (resizeableCropView.cropBorderView.frame.size.width < 60 || resizeableCropView.cropBorderView.frame.size.height < 60 )
            return [super hitTest:point withEvent:event];
        
        CGRect innerTouchFrame = CGRectInset(resizeableCropView.cropBorderView.frame, 30, 30);
        if (CGRectContainsPoint(innerTouchFrame, point))
            return self.scrollView;
        
        CGRect outBorderTouchFrame = CGRectInset(resizeableCropView.cropBorderView.frame, -10, -10);
        if (CGRectContainsPoint(outBorderTouchFrame, point))
            return [super hitTest:point withEvent:event];
        
        return [super hitTest:point withEvent:event];
    }
    return self.scrollView;
}

- (void)layoutSubviews{
    [super layoutSubviews];
    
    CGSize size = self.cropSize;
    CGFloat toolbarSize = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 0 : 54;
    self.xOffset = floor((CGRectGetWidth(self.bounds) - size.width) * 0.5);
    self.yOffset = floor((CGRectGetHeight(self.bounds) - toolbarSize - size.height) * 0.5); //fixed
    
    CGFloat height = self.imageToCrop.size.height;
    CGFloat width = self.imageToCrop.size.width;
    
    CGFloat faktor = 0.f;
    CGFloat faktoredHeight = 0.f;
    CGFloat faktoredWidth = 0.f;
    
    CGFloat zoomScale = 1.0f;
    
    CGFloat targetRatio = size.width / size.height;
    CGFloat imageRatio = width / height;
    
    if(width > height){

        zoomScale = imageRatio/targetRatio;
        
        faktor = width / size.width;
        faktoredWidth = size.width;
        faktoredHeight =  height / faktor;
        
    } else {
        
        zoomScale = targetRatio/imageRatio;
        
        faktor = height / size.height;
        faktoredWidth = width / faktor;
        faktoredHeight =  size.height;
    }
    
    self.cropOverlayView.frame = self.bounds;
    self.scrollView.frame = CGRectMake(xOffset, yOffset, size.width, size.height);
    self.scrollView.contentSize = CGSizeMake(size.width, size.height);
    self.imageView.frame = CGRectMake(0, floor((size.height - faktoredHeight) * 0.5), faktoredWidth, faktoredHeight);

    self.scrollView.minimumZoomScale = zoomScale;
    self.scrollView.zoomScale = zoomScale;
    [self.scrollView updateConstraints];
}

#pragma mark -
#pragma UIScrollViewDelegate Methods

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView{
    return self.imageView;
}

@end