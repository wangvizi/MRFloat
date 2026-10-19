#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <substrate.h>

#pragma mark - 悬浮窗（每个视频一个独立 UIWindow）

@interface MRFloatViewController : UIViewController
@end

@implementation MRFloatViewController
@end

@interface MRFloatWindow : UIWindow
@end

@implementation MRFloatWindow {
    AVPlayer *_player;
    AVPlayerLayer *_playerLayer;
    UIButton *_muteBtn;
    BOOL _muted;
}

- (instancetype)initWithURL:(NSURL *)url index:(NSUInteger)index {
    CGFloat w = 180, h = 110;
    CGFloat x = 10 + (index % 2) * (w + 10);
    CGFloat y = 90 + (index / 2) * (h + 12);

    if ((self = [super initWithFrame:CGRectMake(x, y, w, h)])) {
        self.windowLevel = UIWindowLevelAlert + 5;
        self.backgroundColor = [UIColor clearColor];

        MRFloatViewController *vc = [MRFloatViewController new];
        vc.view.backgroundColor = [UIColor blackColor];
        vc.view.layer.cornerRadius = 10;
        vc.view.layer.masksToBounds = YES;
        vc.view.layer.borderColor = [UIColor whiteColor].CGColor;
        vc.view.layer.borderWidth = 1;
        self.rootViewController = vc;

        _player = [AVPlayer playerWithURL:url];
        _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
        _playerLayer.frame = vc.view.bounds;
        _playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        [vc.view.layer addSublayer:_playerLayer];

        NSString *name = url.lastPathComponent.length ? url.lastPathComponent : @"视频";
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(8, 6, 130, 15)];
        title.text = [NSString stringWithFormat:@"#%lu %@", (unsigned long)(index + 1), name];
        title.font = [UIFont boldSystemFontOfSize:10];
        title.textColor = [UIColor whiteColor];
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        [vc.view addSubview:title];

        _muteBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _muteBtn.frame = CGRectMake(w - 58, 4, 28, 24);
        [_muteBtn setTitle:@"🔈" forState:UIControlStateNormal];
        _muteBtn.tintColor = [UIColor whiteColor];
        [_muteBtn addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];
        [vc.view addSubview:_muteBtn];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(w - 30, 4, 28, 24);
        [close setTitle:@"✕" forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        close.tintColor = [UIColor whiteColor];
        [close addTarget:self action:@selector(close_) forControlEvents:UIControlEventTouchUpInside];
        [vc.view addSubview:close];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan_:)];
        [vc.view addGestureRecognizer:pan];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap_:)];
        [vc.view addGestureRecognizer:tap];

        [_player play];
        self.hidden = NO;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _playerLayer.frame = self.rootViewController.view.bounds;
}

- (void)pan_:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:nil];
    CGRect f = self.frame;
    f.origin.x += t.x;
    f.origin.y += t.y;
    self.frame = f;
    [g setTranslation:CGPointZero inView:nil];
}

- (void)tap_:(UITapGestureRecognizer *)g {
    if (_player.rate > 0) {
        [_player pause];
    } else {
        [_player play];
    }
}

- (void)toggleMute {
    _muted = !_muted;
    _player.muted = _muted;
    [_muteBtn setTitle:_muted ? @"🔇" : @"🔈" forState:UIControlStateNormal];
}

- (void)close_ {
    [_player pause];
    [_playerLayer removeFromSuperlayer];
    _player = nil;
    self.hidden = YES;
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
    NSMutableSet<NSString *> *_keys;
    NSMutableDictionary<NSString *, MRFloatWindow *> *_windows;
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
        _keys = [NSMutableSet set];
        _windows = [NSMutableDictionary dictionary];
        _index = 0;
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
    NSUInteger idx = 0;
    @synchronized (self) {
        if ([_keys containsObject:key]) return;
        [_keys addObject:key];
        idx = _index++;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        MRFloatWindow *w = [[MRFloatWindow alloc] initWithURL:url index:idx];
        @synchronized (self) {
            _windows[key] = w;
        }
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