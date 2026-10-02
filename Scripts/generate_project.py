"""Generate the checked-in Xcode project with Python's standard library.

Run after adding/removing app or native test files. No XcodeGen dependency.
"""
from pathlib import Path
import hashlib
import json
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Folio.xcodeproj"


def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def quote(value):
    return json.dumps(value)


def generate():
    objects = []

    def add(key, body):
        objects.append(f"\t\t{uid(key)} = {{ {body} }};")
        return uid(key)

    def sequence(values):
        return "(" + ", ".join(values) + ",)" if values else "()"

    def files(folder):
        refs, builds = [], []
        for path in sorted((ROOT / folder).rglob("*.swift")):
            relative = path.relative_to(ROOT / folder).as_posix()
            key = folder + "/" + relative
            ref = add("file:" + key, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(relative)}; sourceTree = \"<group>\";")
            refs.append(ref)
            builds.append(add("build:" + key, f"isa = PBXBuildFile; fileRef = {ref};"))
        return refs, builds

    app_refs, app_builds = files("Folio")
    test_refs, test_builds = files("FolioTests")
    resources = []
    for name, filetype in [("Assets.xcassets", "folder.assetcatalog"), ("PrivacyInfo.xcprivacy", "text.xml"), ("Localizable.xcstrings", "text.json.xcstrings")]:
        ref = add("resource:" + name, f"isa = PBXFileReference; lastKnownFileType = {filetype}; path = {quote('Resources/' + name)}; sourceTree = \"<group>\";")
        app_refs.append(ref)
        resources.append(add("resource-build:" + name, f"isa = PBXBuildFile; fileRef = {ref};"))
    app_refs.append(add("info", 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Resources/Info.plist; sourceTree = "<group>";'))
    product = add("app-product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Folio.app; sourceTree = BUILT_PRODUCTS_DIR;')
    tests_product = add("test-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = FolioTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    package = add("package", 'isa = XCLocalSwiftPackageReference; relativePath = .;')
    core = add("core-product", 'isa = XCSwiftPackageProductDependency; productName = FolioCore;')
    core_test = add("core-test-product", 'isa = XCSwiftPackageProductDependency; productName = FolioCore;')
    core_build = add("core-build", f"isa = PBXBuildFile; productRef = {core};")
    core_test_build = add("core-test-build", f"isa = PBXBuildFile; productRef = {core_test};")
    app_group = add("app-group", f"isa = PBXGroup; children = {sequence(app_refs)}; path = Folio; sourceTree = \"<group>\";")
    tests_group = add("tests-group", f"isa = PBXGroup; children = {sequence(test_refs)}; path = FolioTests; sourceTree = \"<group>\";")
    products_group = add("products-group", f"isa = PBXGroup; children = {sequence([product, tests_product])}; name = Products; sourceTree = \"<group>\";")
    main_group = add("main-group", f"isa = PBXGroup; children = {sequence([app_group, tests_group, products_group])}; sourceTree = \"<group>\";")

    def phase(key, kind, values):
        return add(key, f"isa = PBX{kind}BuildPhase; buildActionMask = 2147483647; files = {sequence(values)}; runOnlyForDeploymentPostprocessing = 0;")

    app_phases = [phase("app-sources", "Sources", app_builds), phase("app-frameworks", "Frameworks", [core_build]), phase("app-resources", "Resources", resources)]
    test_phases = [phase("test-sources", "Sources", test_builds), phase("test-frameworks", "Frameworks", [core_test_build]), phase("test-resources", "Resources", [])]
    base = {"SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos", "CLANG_ENABLE_MODULES": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17", "ENABLE_USER_SCRIPT_SANDBOXING": "YES"}

    def configs(key, values):
        identifiers = []
        for name in ["Debug", "Release"]:
            settings = dict(values)
            settings.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O", "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym"})
            if name == "Debug":
                settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
                settings["ENABLE_TESTABILITY"] = "YES"
            body = " ".join(f"{option} = {quote(value)};" for option, value in sorted(settings.items()))
            identifiers.append(add(key + name, f"isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {name};"))
        return add(key + "list", f"isa = XCConfigurationList; buildConfigurations = {sequence(identifiers)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")

    project_configs = configs("project-config", base)
    app_configs = configs("app-config", {"PRODUCT_BUNDLE_IDENTIFIER": "app.folio.dictionary", "PRODUCT_NAME": "$(TARGET_NAME)", "INFOPLIST_FILE": "Folio/Resources/Info.plist", "GENERATE_INFOPLIST_FILE": "NO", "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "MARKETING_VERSION": "0.1.0", "CURRENT_PROJECT_VERSION": "1", "ENABLE_PREVIEWS": "YES", "SWIFT_EMIT_LOC_STRINGS": "YES", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"})
    test_configs = configs("test-config", {"PRODUCT_BUNDLE_IDENTIFIER": "app.folio.dictionary.tests", "PRODUCT_NAME": "$(TARGET_NAME)", "GENERATE_INFOPLIST_FILE": "YES", "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "CODE_SIGN_STYLE": "Automatic", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Folio.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Folio", "BUNDLE_LOADER": "$(TEST_HOST)", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"})
    proxy = add("test-proxy", f"isa = PBXContainerItemProxy; containerPortal = {uid('project')}; proxyType = 1; remoteGlobalIDString = {uid('app-target')}; remoteInfo = Folio;")
    dependency = add("test-dependency", f"isa = PBXTargetDependency; target = {uid('app-target')}; targetProxy = {proxy};")
    app_target = add("app-target", f"isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {sequence(app_phases)}; buildRules = (); dependencies = (); name = Folio; packageProductDependencies = {sequence([core])}; productName = Folio; productReference = {product}; productType = \"com.apple.product-type.application\";")
    test_target = add("test-target", f"isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = {sequence(test_phases)}; buildRules = (); dependencies = {sequence([dependency])}; name = FolioTests; packageProductDependencies = {sequence([core_test])}; productName = FolioTests; productReference = {tests_product}; productType = \"com.apple.product-type.bundle.unit-test\";")
    regions = sequence(["en", quote("zh-Hans"), "Base"])
    add("project", f"isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {app_target} = {{CreatedOnToolsVersion = 16.0;}}; {test_target} = {{CreatedOnToolsVersion = 16.0; TestTargetID = {app_target};}}; }}; }}; buildConfigurationList = {project_configs}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = {regions}; mainGroup = {main_group}; packageReferences = {sequence([package])}; productRefGroup = {products_group}; projectDirPath = \"\"; projectRoot = \"\"; targets = {sequence([app_target, test_target])};")
    PROJECT.mkdir(exist_ok=True)
    content = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {uid('project')};\n}}\n"
    (PROJECT / "project.pbxproj").write_text(content, encoding="utf-8")
    schemes = PROJECT / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)

    def reference(identifier, filename, target):
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier}" BuildableName="{escape(filename)}" BlueprintName="{target}" ReferencedContainer="container:Folio.xcodeproj"/>'

    app_ref = reference(app_target, "Folio.app", "Folio")
    test_ref = reference(test_target, "FolioTests.xctest", "FolioTests")
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
  <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{test_ref}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    (schemes / "Folio.xcscheme").write_text(scheme, encoding="utf-8")
    print(f"Generated Folio.xcodeproj ({len(app_builds)} app sources, {len(test_builds)} test sources).")


if __name__ == "__main__":
    generate()
