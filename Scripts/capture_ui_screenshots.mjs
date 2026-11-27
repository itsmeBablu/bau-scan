// Run from the repository root on a Mac with Xcode, XcodeGen and Node.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const output = (...command) => execFileSync(command[0], command.slice(1), { encoding: 'utf8' }).trim();
const run = (...command) => execFileSync(command[0], command.slice(1), { stdio: 'inherit' });
const simctl = (...args) => output('xcrun', 'simctl', ...args);

function selectDevices() {
    const { devices } = JSON.parse(simctl('list', 'devices', 'available', '-j'));
    const runtimes = Object.keys(devices)
        .filter(key => Number(key.match(/\.iOS-(\d+)/)?.[1]) >= 18)
        .sort((a, b) => b.localeCompare(a, 'en', { numeric: true }));
    for (const runtime of runtimes) {
        const models = ['iPhone', 'iPad'].map(family =>
            devices[runtime].find(device => device.isAvailable && device.name.startsWith(family) && device.deviceTypeIdentifier));
        if (models.every(Boolean)) return models.map(model => ({ model, runtime }));
    }
    throw new Error('Xcode needs an iOS 18+ simulator runtime with both an iPhone and an iPad device.');
}

async function captureScreen(device, bundle, root, destination, language, appearance, file) {
    const marker = join(root, 'screenshot-ready');
    rmSync(marker, { force: true });
    simctl('launch', '--terminate-running-process', device, bundle, '-RoomScannerStorageRoot', root,
        '-RoomScannerScreenshot', destination, '-renovation.onboarded', 'YES',
        '-ui.appearance', appearance, '-renovation.language', language,
        '-AppleLanguages', '(' + language + ')', '-AppleLocale', language === 'de' ? 'de_DE' : 'en_GB');
    try {
        const deadline = Date.now() + 30000;
        while (!(existsSync(marker) && readFileSync(marker, 'utf8') === destination)) {
            if (Date.now() > deadline) throw new Error('Timed out opening ' + destination + ' on ' + device);
            await delay(200);
        }
        await delay(1000); // Allow sheet transitions and thumbnail presentation to finish.
        simctl('io', device, 'screenshot', '--type=png', file);
        const png = readFileSync(file);
        if (png.length < 24 || png.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') {
            throw new Error('Invalid screenshot: ' + file);
        }
        return { width: png.readUInt32BE(16), height: png.readUInt32BE(20) };
    } finally {
        simctl('terminate', device, bundle);
    }
}

async function main() {
    if (process.platform !== 'darwin') throw new Error('Apple simulator screenshots require macOS and Xcode.');
    const models = selectDevices();
    const base = resolve('build/ui-screenshots');
    mkdirSync(base, { recursive: true });
    const directory = mkdtempSync(join(base, 'run-'));
    const derived = resolve('build/ui-screenshot-derived');
    const manifest = {
        commit: output('git', 'rev-parse', 'HEAD'),
        workingTree: output('git', 'status', '--porcelain'),
        xcode: output('xcodebuild', '-version'),
        images: [],
    };
    console.log('Screenshot directory:', directory);
    run('xcodegen', 'generate');
    for (const { model, runtime } of models) {
        const device = simctl('create', 'dWalkScan screenshots ' + model.name, model.deviceTypeIdentifier, runtime);
        try {
            simctl('boot', device);
            run('xcrun', 'simctl', 'bootstatus', device, '-b');
            run('xcodebuild', '-project', 'RoomScanner.xcodeproj', '-scheme', 'RoomScanner',
                '-configuration', 'Debug', '-destination', 'platform=iOS Simulator,id=' + device,
                '-derivedDataPath', derived, '-parallel-testing-enabled', 'NO',
                '-only-testing:RoomScannerTests/DemoDataTests/testWriteDemoStorage',
                'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'test');
            const bundle = output('/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleIdentifier',
                join(derived, 'Build/Products/Debug-iphonesimulator/dWalkScan.app/Info.plist'));
            const root = join(simctl('get_app_container', device, bundle, 'data'), 'tmp/RoomScannerDemo');
            if (!existsSync(root)) throw new Error('Hosted demo test did not seed ' + root);
            simctl('status_bar', device, 'override', '--time', '9:41');
            for (const [language, appearance] of [['en', 'light'], ['de', 'dark']]) {
                simctl('ui', device, 'appearance', appearance);
                for (const destination of ['projects', 'dashboard', 'scanSetup', 'gallery']) {
                    const file = [model.name.split(' ')[0], destination, language, appearance].join('-') + '.png';
                    const size = await captureScreen(device, bundle, root, destination, language, appearance, join(directory, file));
                    manifest.images.push({ file, model: model.name, runtime, destination, language, appearance, ...size });
                    writeFileSync(join(directory, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
                }
            }
        } finally {
            // This UUID belongs to the disposable device created by this run.
            simctl('delete', device);
        }
    }
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
