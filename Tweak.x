// 讓 Google Maps 導航說話時不再壓低音樂：
// 把音訊工作階段的 DuckOthers 選項拿掉，改成與其他聲音混音。
#import <AVFoundation/AVFoundation.h>

static AVAudioSessionCategoryOptions fixOptions(NSString *cat, AVAudioSessionCategoryOptions o) {
    if (!(o & AVAudioSessionCategoryOptionDuckOthers)) return o;
    o &= ~AVAudioSessionCategoryOptionDuckOthers;
    // MixWithOthers 只能用在這幾種類別，否則會設定失敗
    if ([cat isEqualToString:AVAudioSessionCategoryPlayback] ||
        [cat isEqualToString:AVAudioSessionCategoryPlayAndRecord] ||
        [cat isEqualToString:AVAudioSessionCategoryMultiRoute]) {
        o |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    NSLog(@"[GoogleMapsNoDuck] removed DuckOthers, category=%@ options=%lu", cat, (unsigned long)o);
    return o;
}

%hook AVAudioSession

- (BOOL)setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    return %orig(category, fixOptions(category, options), outError);
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    return %orig(category, mode, fixOptions(category, options), outError);
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode routeSharingPolicy:(AVAudioSessionRouteSharingPolicy)policy options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    return %orig(category, mode, policy, fixOptions(category, options), outError);
}

%end
