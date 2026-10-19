#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <substrate.h>

#pragma mark - 悬浮窗视图

@interface MRFloatItemView : UIView
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@end

@implementation MRFloatItemView

- (instancetype)initWithURL:(NSURL *)url index:(NSUInteger)index {
    CGFloat w = 176, h = 99;
    CGFloat x = [UIScreen mainScreen].bounds.size.width - w - 12;
    CGFloat y = 88 + (h + 12) * (index % 5);
    if ((self = [super initWithFrame:CGRectMake(x, y, w, h)])) {
        self.backgroundColor = [UIColor blackColor];
        self.layer.cornerRadius = 10;
        self.layer.masksToBounds = YES;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        self.layer.borderWidth = 1;

        self.player = [AVPlayer playerWithURL:url];
        self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
        self.playerLayer.frame = self.bounds;
        self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        [self.layer addSublayer:self.playerLayer];

        NSString *name = url.lastPathComponent.length ? url.lastPathComponent : @"悬浮视频";
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(8, 6, 112, 16)];
        title.text = name;
        title.font = [UIFont boldSystemFontOfSize:11];
        title.textColor = [UIColor whiteColor];
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:title];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(w - 30, 2, 28, 28);
        [close setTitle:@"✕" forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        close.tintColor = [UIColor whiteColor];
        [close addTarget:self action:@selector(close_) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:close];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan_:)];
        [self addGestureRecognizer:pan];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap_:)];
        [self addGestureRecognizer:tap];

        [self.player play];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.playerLayer.frame = self.bounds;
}

- (void)pan_:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    CGPoint c = self.center;
    c.x += t.x;
    c.y += t.y;
    self.center = c;
    [g setTranslation:CGPointZero inView:self.superview];
}

- (void)tap_:(UITapGestureRecognizer *)g {
    if (self.player.rate > 0) {
        [self.player pause];
    } else {
        [self.player play];
    }
}

- (void)close_ {
    [self.player pause];
    [self.playerLayer removeFromSuperlayer];
    self.player = nil;
    [self removeFromSuperview];
}

@end

#pragma mark - 悬浮窗管理

@interface MRFloatManager : NSObject
+ (instancetype)shared;
+ (void)offerURL:(NSURL *)url;
+ (void)offerAsset:(AVAsset *)asset;
- (void)presentURL:(NSURL *)url;
@end

@implementation MRFloatManager {
    UIWindow *_window;
    NSMutableSet<NSString *> *_seen;
    NSUInteger _index;
}

+ (instancetype)shared {
    static id m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = [self new];
    });
    return m;
}

- (instancetype)init {
    if ((self = [super init])) {
        _seen = [NSMutableSet set];
        _index = 0;
        _window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        _window.windowLevel = UIWindowLevelAlert + 2;
        _window.backgroundColor = [UIColor clearColor];
        _window.rootViewController = [UIViewController new];
        _window.rootViewController.view.backgroundColor = [UIColor clearColor];
        _window.userInteractionEnabled = YES;
        _window.hidden = NO;
    }
    return self;
}

+ (void)offerAsset:(AVAsset *)asset {
    if ([asset isKindOfClass:[AVURLAsset class]]) {
        [self offerURL:[(AVURLAsset *)asset URL]];
    }
}

+ (void)offerURL:(NSURL *)url {
    if (!url) return;
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        [[self shared] presentURL:url];
    }
}

- (void)presentURL:(NSURL *)url {
    NSString *key = url.absoluteString;
    @synchronized (_seen) {
        if ([_seen containsObject:key]) return;
        [_seen addObject:key];
    }
    NSUInteger idx = _index++;
    dispatch_async(dispatch_get_main_queue(), ^{
        MRFloatItemView *item = [[MRFloatItemView alloc] initWithURL:url index:idx];
        [_window.rootViewController.view addSubview:item];
    });
}

@end

#pragma mark - Hook AVPlayer

%hook AVPlayer

- (id)initWithPlayerItem:(AVPlayerItem *)item {
    id ret = %orig;
    if (item) {
        [MRFloatManager offerAsset:item.asset];
    }
    return ret;
}

- (id)initWithURL:(NSURL *)URL {
    id ret = %orig;
    [MRFloatManager offerURL:URL];
    return ret;
}

- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    %orig;
    if (item) {
        [MRFloatManager offerAsset:item.asset];
    }
}

%end

%ctor {}