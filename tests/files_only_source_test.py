import re,subprocess,sys
def r(p): return open(p).read()
root=r('src/RootTabBarController.m'); app=r('src/AppDelegate.m')
for bad in ('SettingsVC','GestaltVC','PosterBoardVC'):
    assert bad not in root, bad
assert root.count('ReadOnlyBrowserVC alloc')==1 and 'self.viewControllers = @[n];' in root
assert 'ForceLeftToRight' in root
for bad in ('BQCoreInit','bqselftest','BQUI','BQCore','Selftest'):
    assert bad not in app, bad
assert 'SceneConfiguration' in app or 'UISceneConfiguration' in app
for f in ('src/BQCore.m','src/BQCore.h','src/ROAccess.h','src/GBSafeWrite.h','src/entitlements.plist'):
    d=subprocess.run(['git','diff','--quiet','0ed50b5','--',f]).returncode
    assert d==0, f+' changed'
print('files_only_source_test PASS')
h=r('tests/browser_smoke.m'); sh=r('tests/browser_smoke.sh')
assert '#import "RootTabBarController.h"' in h and 'RootTabBarController new' in h
assert 'RootTabBarController.m' in sh
assert 'SMOKE_FILES_ONLY_PASS' in h and 'SMOKE_FILES_ONLY_PASS' in sh
