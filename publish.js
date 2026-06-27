const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const axios = require('axios');
const FormData = require('form-data');
const readline = require('readline');

// Use this for local testing
// const BASE_URL = 'http://10.10.243.44:3000'; 
// Use this for production
const BASE_URL = 'https://collection.acmagencies.store'; 
let ADMIN_TOKEN = '';

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

const question = (query) => new Promise(resolve => rl.question(query, resolve));

async function publish() {
  console.log('--- App Update Publisher ---');
  
  const platform = await question('Platform (android/windows): ');
  if (!['android', 'windows'].includes(platform.toLowerCase())) {
    console.error('Invalid platform.');
    process.exit(1);
  }

  const version = await question('Version (e.g., 1.0.1): ');
  const releaseNotes = await question('Release Notes: ');
  const forceUpdateStr = await question('Force Update? (y/N): ');
  const forceUpdate = forceUpdateStr.toLowerCase() === 'y';
  const adminEmail = await question('Admin Email: ');
  const adminPassword = await question('Admin Password: ');

  try {
    // 1. Authenticate
    console.log('\nAuthenticating...');
    const authRes = await axios.post(`${BASE_URL}/api/auth/login`, {
      email: adminEmail,
      password: adminPassword
    });
    ADMIN_TOKEN = authRes.data.token;
    if (authRes.data.role !== 'admin') {
      throw new Error('Must be an admin to publish updates.');
    }

    // 1.5 Update pubspec.yaml version automatically
    console.log(`\nUpdating pubspec.yaml to version ${version}...`);
    const pubspecPath = path.join(__dirname, 'pubspec.yaml');
    let pubspecContent = fs.readFileSync(pubspecPath, 'utf8');
    
    let currentBuildNumber = 1;
    const versionMatch = pubspecContent.match(/version:\s+\d+\.\d+\.\d+\+(\d+)/);
    if (versionMatch) {
      currentBuildNumber = parseInt(versionMatch[1], 10) + 1;
    }
    
    pubspecContent = pubspecContent.replace(/version:\s+\d+\.\d+\.\d+(\+\d+)?/, `version: ${version}+${currentBuildNumber}`);
    fs.writeFileSync(pubspecPath, pubspecContent);

    // 2. Build the app
    console.log(`\nBuilding for ${platform}...`);
    if (platform === 'android') {
      execSync('flutter build apk --release', { stdio: 'inherit' });
    } else {
      execSync('flutter build windows --release', { stdio: 'inherit' });
      console.log('\nCreating Windows Installer using Inno Setup...');
      
      let isccCommand = 'iscc';
      const possiblePaths = [
        'C:\\Program Files\\Inno Setup 7\\ISCC.exe',
        'C:\\Program Files (x86)\\Inno Setup 6\\ISCC.exe',
        'C:\\Program Files\\Inno Setup 6\\ISCC.exe',
      ];
      
      for (const p of possiblePaths) {
        if (fs.existsSync(p)) {
          isccCommand = `"${p}"`;
          break;
        }
      }

      execSync(`${isccCommand} windows_packaging\\installer.iss`, { stdio: 'inherit' });
    }

    // 3. Upload binary
    console.log('\nUploading binary to server...');
    const formData = new FormData();
    const filePath = platform === 'android' 
      ? path.join(__dirname, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk')
      : path.join(__dirname, 'build', 'windows', 'installer', 'Setup.exe');

    if (!fs.existsSync(filePath)) {
      throw new Error(`File not found: ${filePath}`);
    }

    formData.append('file', fs.createReadStream(filePath));

    const uploadRes = await axios.post(`${BASE_URL}/api/app-version/upload-binary`, formData, {
      headers: {
        'Authorization': `Bearer ${ADMIN_TOKEN}`,
        ...formData.getHeaders()
      }
    });

    const fileUrl = uploadRes.data.url;
    console.log(`Binary uploaded successfully! Accessible at: ${fileUrl}`);

    // 4. Update Version Database
    console.log('\nPublishing new version to database...');
    // The device needs full URL to download it
    const fullUrl = `${BASE_URL}${fileUrl}`;
    
    await axios.post(`${BASE_URL}/api/app-version/publish`, {
      platform: platform,
      version: version,
      url: fullUrl,
      forceUpdate: forceUpdate,
      releaseNotes: releaseNotes
    }, {
      headers: { 'Authorization': `Bearer ${ADMIN_TOKEN}` }
    });

    console.log('\n✅ Update published successfully!');

  } catch (err) {
    console.error('\n❌ Error:', err.response?.data?.message || err.message);
  } finally {
    rl.close();
  }
}

publish();
