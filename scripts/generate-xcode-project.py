#!/usr/bin/env python3
"""Generate the checked-in Xcode project without third-party tooling."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent
project = root / 'FolderHop.xcodeproj'
project.mkdir(exist_ok=True)
objects = []

def uid(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()

def q(value):
    return json.dumps(str(value), ensure_ascii=False)

def add(key, isa, body):
    objects.append(f'{uid(key)} = {{isa = {isa}; {body} }};')
    return uid(key)

def ids(keys):
    return '(' + ', '.join(uid(key) for key in keys) + ',)'

sources = {}
for target, folder in [('core', 'Sources/FolderCore'), ('app', 'Sources/FolderHop'), ('tests', 'Tests/FolderCoreTests')]:
    sources[target] = []
    for file in sorted((root / folder).glob('*.swift')):
        key = str(file.relative_to(root))
        add(key, 'PBXFileReference', f'lastKnownFileType = sourcecode.swift; path = {q(file.name)}; sourceTree = "<group>";')
        add(key + ':build', 'PBXBuildFile', f'fileRef = {uid(key)};')
        sources[target].append(key)
    add(target + ':group', 'PBXGroup', f'path = {q(folder)}; sourceTree = "<group>"; children = {ids(sources[target])};')

resources = ['Resources/AppIcon.icns', 'Resources/Info.plist', 'Resources/FolderHop.entitlements', 'Resources/ThirdParty']
for path in resources:
    file_type = 'folder' if path.endswith('ThirdParty') else ('image.icns' if path.endswith('icns') else 'text.plist.xml')
    add(path, 'PBXFileReference', f'lastKnownFileType = {file_type}; path = {q(Path(path).name)}; sourceTree = "<group>";')
for path in [resources[0], resources[3]]:
    add(path + ':build', 'PBXBuildFile', f'fileRef = {uid(path)};')
add('resources:group', 'PBXGroup', f'path = Resources; sourceTree = "<group>"; children = {ids(resources)};')

for target, name, file_type in [('core', 'FolderCore.framework', 'wrapper.framework'), ('app', 'FolderHop.app', 'wrapper.application'), ('tests', 'FolderCoreTests.xctest', 'wrapper.cfbundle')]:
    add(target + ':product', 'PBXFileReference', f'explicitFileType = {file_type}; path = {q(name)}; sourceTree = BUILT_PRODUCTS_DIR;')
add('products', 'PBXGroup', f'name = Products; sourceTree = "<group>"; children = {ids([t + ":product" for t in sources])};')
add('root', 'PBXGroup', f'sourceTree = "<group>"; children = {ids(["app:group", "core:group", "tests:group", "resources:group", "products"])};')

for target in sources:
    add(target + ':sources', 'PBXSourcesBuildPhase', f'buildActionMask = 2147483647; files = {ids([s + ":build" for s in sources[target]])}; runOnlyForDeploymentPostprocessing = 0;')
    frameworks = []
    if target != 'core':
        link = target + ':core-link'
        add(link, 'PBXBuildFile', f'fileRef = {uid("core:product")};')
        frameworks.append(link)
        add(target + ':proxy', 'PBXContainerItemProxy', f'containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("core:target")}; remoteInfo = FolderCore;')
        add(target + ':dependency', 'PBXTargetDependency', f'target = {uid("core:target")}; targetProxy = {uid(target + ":proxy")};')
    add(target + ':frameworks', 'PBXFrameworksBuildPhase', f'buildActionMask = 2147483647; files = {ids(frameworks) if frameworks else "()"}; runOnlyForDeploymentPostprocessing = 0;')
add('app:resources', 'PBXResourcesBuildPhase', f'buildActionMask = 2147483647; files = {ids([resources[0] + ":build", resources[3] + ":build"])}; runOnlyForDeploymentPostprocessing = 0;')

common = {
    'MACOSX_DEPLOYMENT_TARGET': '14.0', 'SDKROOT': 'macosx', 'SWIFT_VERSION': '5.0',
    'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES',
    'ENABLE_USER_SCRIPT_SANDBOXING': 'YES', 'SWIFT_EMIT_LOC_STRINGS': 'NO',
}
target_settings = {
    'core': {'PRODUCT_NAME': 'FolderCore', 'PRODUCT_BUNDLE_IDENTIFIER': 'app.folderhop.core', 'DEFINES_MODULE': 'YES', 'MACH_O_TYPE': 'staticlib', 'SKIP_INSTALL': 'YES', 'GENERATE_INFOPLIST_FILE': 'YES', 'CODE_SIGNING_ALLOWED': 'NO'},
    'app': {'PRODUCT_NAME': 'FolderHop', 'PRODUCT_BUNDLE_IDENTIFIER': 'app.folderhop.mac', 'INFOPLIST_FILE': 'Resources/Info.plist', 'CODE_SIGN_ENTITLEMENTS': 'Resources/FolderHop.entitlements', 'CODE_SIGN_IDENTITY': '-', 'CODE_SIGN_STYLE': 'Manual', 'ENABLE_HARDENED_RUNTIME': 'YES', 'COMBINE_HIDPI_IMAGES': 'YES', 'ENABLE_DEBUG_DYLIB': 'NO'},
    'tests': {'PRODUCT_NAME': 'FolderCoreTests', 'PRODUCT_BUNDLE_IDENTIFIER': 'app.folderhop.tests', 'GENERATE_INFOPLIST_FILE': 'YES', 'CODE_SIGNING_ALLOWED': 'NO', 'ENABLE_TESTABILITY': 'YES'},
}
for scope in ['project', *sources]:
    configs = []
    for config in ['Debug', 'Release']:
        settings = dict(common if scope == 'project' else target_settings[scope])
        if scope == 'project':
            settings.update({'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if config == 'Debug' else '-O', 'DEBUG_INFORMATION_FORMAT': 'dwarf' if config == 'Debug' else 'dwarf-with-dsym'})
            if config == 'Debug':
                settings.update({'ENABLE_TESTABILITY': 'YES', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG', 'ONLY_ACTIVE_ARCH': 'YES'})
        key = scope + ':' + config
        add(key, 'XCBuildConfiguration', 'buildSettings = {' + ' '.join(f'{k} = {q(v)};' for k, v in settings.items()) + f'}}; name = {config};')
        configs.append(key)
    add(scope + ':config', 'XCConfigurationList', f'buildConfigurations = {ids(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

for target, name, product_type in [('core', 'FolderCore', 'framework'), ('app', 'FolderHop', 'application'), ('tests', 'FolderCoreTests', 'bundle.unit-test')]:
    phases = [target + ':sources', target + ':frameworks'] + (['app:resources'] if target == 'app' else [])
    dependencies = ids([target + ':dependency']) if target != 'core' else '()'
    add(target + ':target', 'PBXNativeTarget', f'buildConfigurationList = {uid(target + ":config")}; buildPhases = {ids(phases)}; buildRules = (); dependencies = {dependencies}; name = {name}; productName = {name}; productReference = {uid(target + ":product")}; productType = "com.apple.product-type.{product_type}";')

add('project', 'PBXProject', f'attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600;}}; buildConfigurationList = {uid("project:config")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-HK"; hasScannedForEncodings = 0; knownRegions = ("zh-HK", Base); mainGroup = {uid("root")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = {ids([t + ":target" for t in sources])};')
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {uid("project")};}}\n')

scheme_dir = project / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
def reference(target, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(target + ":target")}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:FolderHop.xcodeproj"/>'

(scheme_dir / 'FolderHop.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference('app', 'FolderHop.app')}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables>
  <TestableReference skipped="NO">{reference('tests', 'FolderCoreTests.xctest')}</TestableReference>
 </Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('app', 'FolderHop.app')}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('app', 'FolderHop.app')}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print('已產生 FolderHop.xcodeproj')
