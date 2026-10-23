from pathlib import Path
import urllib.request, zipfile, subprocess
exec(Path('/data/data/com.ai.assistance.operit/files/workspace/TideBot/.native_check.py').read_text().split('# Compile Android-native sources')[0])
deps=[('https://repo.maven.apache.org/maven2/','com/squareup/okhttp3/okhttp/4.12.0/okhttp-4.12.0.jar'),('https://repo.maven.apache.org/maven2/','com/squareup/okio/okio-jvm/3.6.0/okio-jvm-3.6.0.jar'),('https://maven.aliyun.com/repository/google/','androidx/work/work-runtime/2.10.0/work-runtime-2.10.0.aar'),('https://maven.aliyun.com/repository/google/','androidx/core/core/1.13.1/core-1.13.1.aar'),('https://repo.maven.apache.org/maven2/','com/google/guava/listenablefuture/1.0/listenablefuture-1.0.jar')]
classpath=[Path('/data/data/com.ai.assistance.operit/files/android-sdk/platforms/android-35/android.jar')]+stdlib+jars('org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm','1.9.0')+jars('org.jetbrains/annotations')
for host,path in deps:
    dest=tmp/path.split('/')[-1]
    dest.write_bytes(urllib.request.urlopen(host+path,timeout=25).read())
    if dest.suffix=='.aar':
        extracted=dest.with_suffix('.jar')
        with zipfile.ZipFile(dest) as z: extracted.write_bytes(z.read('classes.jar'))
        dest=extracted
    classpath.append(dest)
# These two integrations need Flutter/plugin binaries, which are not part of this native check.
stub=tmp/'FlutterIntegrationStubs.kt'
stub.write_text('''package com.yutan123.tidebot
class MainActivity : android.app.Activity()
object TideServiceWake { fun start(context: android.content.Context, action: String) {} }
''')
sources=[p for p in k.glob('*.kt') if p.name not in {'MainActivity.kt','TideServiceWake.kt'}]+[stub]
res=subprocess.run(base+['-classpath',':'.join(map(str,classpath)),'-d',str(tmp/'native.jar')]+list(map(str,sources)),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
print(res.stdout,flush=True)
print('Native source compile exit:',res.returncode,flush=True)
print('Check directory:',tmp,flush=True)
raise SystemExit(res.returncode)