from pathlib import Path
import subprocess, tempfile, zipfile, os
r=Path('/data/data/com.ai.assistance.operit/files/workspace/TideBot')
c=Path('/root/.gradle/caches/modules-2/files-2.1')
def jars(module, version=None):
    base=c/module
    return list((base/version if version else base).glob('*/*.jar' if version else '*/*/*.jar'))
compiler=[]
for module,version in [('org.jetbrains.kotlin/kotlin-compiler-embeddable','2.2.20'),('org.jetbrains.kotlin/kotlin-stdlib','2.2.20'),('org.jetbrains.kotlin/kotlin-script-runtime',None),('org.jetbrains.kotlin/kotlin-reflect','2.1.20'),('org.jetbrains.intellij.deps/trove4j',None),('org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm','1.9.0'),('org.jetbrains/annotations',None)]:
    compiler+=jars(module,version)
stdlib=jars('org.jetbrains.kotlin/kotlin-stdlib','2.2.20')
print('Compiler dependencies:',len(compiler),flush=True)
tmp=Path(tempfile.mkdtemp(prefix='tide-native-check-'))
cp=':'.join(map(str,compiler))
base=['java','-Xmx768m','-cp',cp,'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-jvm-target','17']
k=r/'android/app/src/main/kotlin/com/yutan123/tidebot'
cmd=base+['-classpath',':'.join(map(str,stdlib)),'-d',str(tmp/'leases.jar'),str(k/'TideRequestLeases.kt'),str(r/'test/native/TideRequestLeasesCheck.kt')]
res=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True); print(res.stdout,flush=True)
if res.returncode: raise SystemExit(res.returncode)
res=subprocess.run(['java','-cp',str(tmp/'leases.jar')+':'+':'.join(map(str,stdlib)),'com.yutan123.tidebot.TideRequestLeasesCheckKt'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
print(res.stdout,flush=True)
if res.returncode: raise SystemExit(res.returncode)
# Compile Android-native sources against cached public API jars; no APK/build packaging.
classpath=[Path('/data/data/com.ai.assistance.operit/files/android-sdk/platforms/android-35/android.jar')]+stdlib
for module in ['org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm','org.jetbrains.kotlinx/kotlinx-coroutines-android','com.squareup.okhttp3/okhttp','com.squareup.okio/okio-jvm','org.jetbrains/annotations','androidx.annotation/annotation','androidx.annotation/annotation-jvm','com.google.guava/listenablefuture','com.google.guava/guava','androidx.concurrent/concurrent-futures']:
    classpath+=jars(module)
for module in ['androidx.work/work-runtime','androidx.work/work-runtime-ktx','androidx.core/core','androidx.lifecycle/lifecycle-service','androidx.lifecycle/lifecycle-common','androidx.lifecycle/lifecycle-runtime']:
    for aar in (c/module).glob('*/*/*.aar'):
        dest=tmp/(aar.stem+'-'+aar.parent.name+'.jar')
        with zipfile.ZipFile(aar) as z:
            if 'classes.jar' in z.namelist(): dest.write_bytes(z.read('classes.jar')); classpath.append(dest)
sources=[p for p in k.glob('*.kt') if p.name!='MainActivity.kt']
res=subprocess.run(base+['-classpath',':'.join(map(str,classpath)),'-d',str(tmp/'native.jar')]+list(map(str,sources)),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
print(res.stdout,flush=True)
print('Native compile exit:',res.returncode,flush=True)
print('Native check directory:',tmp,flush=True)
raise SystemExit(res.returncode)