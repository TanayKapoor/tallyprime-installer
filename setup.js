#!/usr/bin/env node
'use strict';

const { execSync, spawnSync } = require('child_process');
const fs   = require('fs');
const path = require('path');
const os   = require('os');
const https = require('https');

// ── chalk v4 (CommonJS) ───────────────────────────────────────────────────────
const chalk = require('chalk');

// ── enquirer ──────────────────────────────────────────────────────────────────
const { prompt } = require('enquirer');

// ── helpers ───────────────────────────────────────────────────────────────────
const W = process.stdout.columns || 60;

function rule()  { console.log(chalk.gray('  ' + '─'.repeat(W - 4))); }
function blank() { console.log(''); }
function ok(t)   { console.log(chalk.green('  [OK] ') + t); }
function warn(t) { console.log(chalk.yellow('  [ ! ] ') + t); }
function fail(t) { console.log(chalk.red('  [ X ] ') + t); }
function dim(t)  { console.log(chalk.gray('        ' + t)); }
function step(t) { console.log(chalk.white('   >  ') + t); }

function section(n, title) {
  blank();
  console.log(chalk.cyan(`  ---- ${n} : ${title} ----`));
  blank();
}

function banner() {
  console.clear();
  blank();
  console.log(chalk.green('  +------------------------------------------+'));
  console.log(chalk.green('  |  TallyPrime -> PostgreSQL Pipeline        |'));
  console.log(chalk.green('  |  Milestone 1  |  Environment Setup        |'));
  console.log(chalk.green('  +------------------------------------------+'));
  blank();
  console.log(chalk.white('  This script prepares your system to run the pipeline.'));
  console.log(chalk.gray ('  It checks prerequisites and creates your configuration file.'));
  console.log(chalk.gray ('  The pipeline code will be delivered in a separate step.'));
  blank();
  rule();
  blank();
}

function run(cmd, opts = {}) {
  return spawnSync(cmd, { shell: true, encoding: 'utf8', ...opts });
}

function ask(questions) {
  return prompt(questions);
}

function pause(msg = 'Press Enter to exit...') {
  return prompt({ type: 'input', name: '_', message: msg });
}

// ── download helper ───────────────────────────────────────────────────────────
function download(url, dest) {
  return new Promise((resolve, reject) => {
    const follow = (u) => {
      https.get(u, (res) => {
        if (res.statusCode === 301 || res.statusCode === 302) {
          return follow(res.headers.location);
        }
        if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode}`));
        const f = fs.createWriteStream(dest);
        res.pipe(f);
        f.on('finish', () => f.close(resolve));
        f.on('error', reject);
      }).on('error', reject);
    };
    follow(url);
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP 1 — Prerequisites
// ══════════════════════════════════════════════════════════════════════════════
async function checkPython() {
  section('Step 1 of 3', 'Prerequisites');

  step('Checking Python...');

  // Disable the Windows Store alias before testing
  // (it causes "python.exe" to emit text to stderr and return exit 9009)
  function getPythonVersion() {
    const r = run('python --version');
    if (r.status !== 0) return null;
    const m = (r.stdout + r.stderr).match(/Python (\d+)\.(\d+)/);
    return m ? { major: +m[1], minor: +m[2], str: `${m[1]}.${m[2]}` } : null;
  }

  async function installPython() {
    // Try winget first
    const wg = run('winget --version');
    if (wg.status === 0) {
      step('Installing Python 3.11 via winget...');
      const r = run(
        'winget install --id Python.Python.3.11 --silent --accept-package-agreements --accept-source-agreements',
        { stdio: 'inherit' }
      );
      if (r.status === 0) {
        ok('Python 3.11 installed via winget');
        return true;
      }
      warn('winget install failed, falling back to direct download...');
    }

    // Fallback: download official installer
    const url  = 'https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe';
    const dest = path.join(os.tmpdir(), 'python-3.11.9-amd64.exe');
    step('Downloading Python 3.11.9 installer (~25 MB)...');
    try {
      await download(url, dest);
      step('Running installer silently (this may take a minute)...');
      run(`"${dest}" /quiet PrependPath=1 Include_pip=1`, { stdio: 'inherit' });
      fs.unlinkSync(dest);
      ok('Python 3.11 installed');
      return true;
    } catch (e) {
      fail(`Download failed: ${e.message}`);
      return false;
    }
  }

  let ver = getPythonVersion();

  if (!ver) {
    warn('Python not found on this machine.');
    const { install } = await ask({
      type: 'confirm', name: 'install',
      message: 'Install Python 3.11 automatically?',
      initial: true,
    });
    if (install) {
      const ok2 = await installPython();
      if (!ok2) {
        fail('Could not install Python automatically.');
        dim('Please install from: https://www.python.org/downloads/');
        dim("Tick 'Add Python to PATH' during install, then re-run.");
        await pause();
        process.exit(1);
      }
      ver = getPythonVersion();
    } else {
      dim('Please install Python 3.11+ from: https://www.python.org/downloads/');
      dim("Tick 'Add Python to PATH' during install, then re-run.");
      await pause();
      process.exit(1);
    }
  }

  if (ver && (ver.major < 3 || (ver.major === 3 && ver.minor < 11))) {
    warn(`Python ${ver.str} found, but 3.11+ is required.`);
    const { install } = await ask({
      type: 'confirm', name: 'install',
      message: 'Install Python 3.11 alongside it?',
      initial: true,
    });
    if (install) {
      await installPython();
      ver = getPythonVersion();
    } else {
      fail('Python 3.11+ is required. Exiting.');
      process.exit(1);
    }
  }

  ok(`Python ${ver ? ver.str : '3.11'} ready`);

  // PostgreSQL check (advisory only)
  blank();
  step('Checking PostgreSQL...');
  const pg = run('psql --version');
  if (pg.status === 0) {
    ok('PostgreSQL client found: ' + (pg.stdout || pg.stderr).trim());
  } else {
    warn('psql not found on PATH.');
    dim('That is fine — you just need a PostgreSQL server accessible over the network.');
    dim('If not installed: https://www.postgresql.org/download/windows/');
    blank();
    const { cont } = await ask({
      type: 'confirm', name: 'cont',
      message: 'Continue anyway?',
      initial: true,
    });
    if (!cont) process.exit(0);
  }

  blank();
  ok('Prerequisites satisfied');
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP 2 — Install directory
// ══════════════════════════════════════════════════════════════════════════════
async function chooseDirectory() {
  section('Step 2 of 3', 'Install Location');

  dim('This is where the pipeline code will be placed when delivered.');
  blank();

  const defaultDir = path.join(os.homedir(), 'TallyPrime-to-Postgres');
  const { dir } = await ask({
    type: 'input', name: 'dir',
    message: 'Install directory',
    initial: defaultDir,
  });

  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
    ok(`Directory created: ${dir}`);
  } else {
    ok(`Directory exists, will use: ${dir}`);
  }

  return dir;
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP 3 — Configuration
// ══════════════════════════════════════════════════════════════════════════════
async function writeEnvFile(dir) {
  section('Step 3 of 3', 'Configuration');

  const envFile = path.join(dir, '.env');

  if (fs.existsSync(envFile)) {
    warn(`.env already exists at ${envFile}`);
    const { overwrite } = await ask({
      type: 'confirm', name: 'overwrite',
      message: 'Overwrite it?',
      initial: false,
    });
    if (!overwrite) {
      ok('Keeping existing .env — skipping configuration.');
      return;
    }
  }

  dim('Press Enter to accept the default shown in parentheses.');
  blank();

  // ── TallyPrime ─────────────────────────────────────────────
  console.log(chalk.gray('  -- TallyPrime Connection --'));
  dim('The machine where TallyPrime is running.');
  const tally = await ask([
    { type: 'input', name: 'host', message: 'Tally host', initial: 'localhost' },
    { type: 'input', name: 'port', message: 'Tally port', initial: '9000' },
  ]);

  // ── PostgreSQL ──────────────────────────────────────────────
  blank();
  console.log(chalk.gray('  -- PostgreSQL Connection --'));
  const { useUrl } = await ask({
    type: 'confirm', name: 'useUrl',
    message: 'Do you have a full DATABASE_URL connection string?',
    initial: false,
  });

  let dbUrl = '', dbHost = '', dbPort = '', dbUser = '', dbPass = '', dbName = '';

  if (useUrl) {
    dim('Format: postgresql+psycopg://user:password@host:5432/dbname');
    const r = await ask({ type: 'input', name: 'url', message: 'DATABASE_URL' });
    dbUrl = r.url;
  } else {
    const r = await ask([
      { type: 'input',    name: 'host', message: 'Host',     initial: 'localhost' },
      { type: 'input',    name: 'port', message: 'Port',     initial: '5432'      },
      { type: 'input',    name: 'user', message: 'Username', initial: 'postgres'  },
      { type: 'password', name: 'pass', message: 'Password'                       },
      { type: 'input',    name: 'name', message: 'Database', initial: 'tallyprime'},
    ]);
    dbHost = r.host; dbPort = r.port; dbUser = r.user; dbPass = r.pass; dbName = r.name;
  }

  // ── Companies ───────────────────────────────────────────────
  blank();
  console.log(chalk.gray('  -- Company Names --'));
  dim('Enter names exactly as they appear in TallyPrime.');
  dim('Separate multiple companies with commas.');
  const { companies } = await ask({
    type: 'input', name: 'companies',
    message: 'Company list',
    initial: 'My Company',
  });

  // ── Sync settings ───────────────────────────────────────────
  blank();
  console.log(chalk.gray('  -- Sync Settings --'));
  const { pollInterval } = await ask({
    type: 'input', name: 'pollInterval',
    message: 'Polling interval in seconds',
    initial: '10',
  });

  // ── SMTP (optional) ─────────────────────────────────────────
  blank();
  console.log(chalk.gray('  -- Email Alerts (optional) --'));
  dim('The pipeline can email you when a sync fails.');
  const { wantSmtp } = await ask({
    type: 'confirm', name: 'wantSmtp',
    message: 'Configure email alerts now?',
    initial: false,
  });

  let smtpHost = '', smtpPort = '', smtpUser = '', smtpPass = '', smtpFrom = '', smtpTo = '';
  if (wantSmtp) {
    const r = await ask([
      { type: 'input',    name: 'host', message: 'SMTP host'       },
      { type: 'input',    name: 'port', message: 'SMTP port',  initial: '587' },
      { type: 'input',    name: 'user', message: 'SMTP username'   },
      { type: 'password', name: 'pass', message: 'SMTP password'   },
      { type: 'input',    name: 'from', message: 'From address'    },
      { type: 'input',    name: 'to',   message: 'Alert recipient' },
    ]);
    smtpHost = r.host; smtpPort = r.port; smtpUser = r.user;
    smtpPass = r.pass; smtpFrom = r.from; smtpTo   = r.to;
  }

  // ── Write file ──────────────────────────────────────────────
  const ts = new Date().toISOString().slice(0, 16).replace('T', ' ');
  const lines = [
    `# TallyPrime -> PostgreSQL -- Environment Configuration`,
    `# Generated by Milestone 1 setup on ${ts}`,
    `# Keep this file private -- do not commit it to version control.`,
    ``,
    `# -- TallyPrime --`,
    `TALLY_HOST=${tally.host}`,
    `TALLY_PORT=${tally.port}`,
    ``,
    `# -- Companies (comma-separated, match TallyPrime exactly) --`,
    `COMPANY_LIST=${companies}`,
    ``,
    `# -- PostgreSQL --`,
    ...(useUrl
      ? [`DATABASE_URL=${dbUrl}`]
      : [`DB_HOST=${dbHost}`, `DB_PORT=${dbPort}`, `DB_USER=${dbUser}`, `DB_PASSWORD=${dbPass}`, `DB_NAME=${dbName}`]
    ),
    ``,
    `# -- Sync --`,
    `POLLING_INTERVAL=${pollInterval}`,
    `DB_POOL_SIZE=5`,
    `DB_MAX_OVERFLOW=10`,
    ``,
    ...(wantSmtp
      ? [`# -- SMTP Alerts --`, `SMTP_HOST=${smtpHost}`, `SMTP_PORT=${smtpPort}`,
         `SMTP_USER=${smtpUser}`, `SMTP_PASSWORD=${smtpPass}`, `SMTP_FROM=${smtpFrom}`, `SMTP_TO=${smtpTo}`]
      : [`# -- SMTP Alerts (disabled -- fill in to enable) --`,
         `# SMTP_HOST=`, `# SMTP_PORT=587`, `# SMTP_USER=`,
         `# SMTP_PASSWORD=`, `# SMTP_FROM=`, `# SMTP_TO=`]
    ),
  ];

  fs.writeFileSync(envFile, lines.join('\n') + '\n', 'utf8');
  blank();
  ok(`.env saved to ${envFile}`);
}

// ══════════════════════════════════════════════════════════════════════════════
// Summary
// ══════════════════════════════════════════════════════════════════════════════
function summary(dir) {
  blank();
  rule();
  blank();
  console.log(chalk.green('  Environment setup complete!'));
  blank();
  console.log(chalk.white(`  Install directory : ${dir}`));
  console.log(chalk.white(`  Config file       : ${path.join(dir, '.env')}`));
  blank();
  console.log(chalk.white('  What was set up:'));
  ok('Python 3.11+ verified');
  ok('PostgreSQL connection details saved');
  ok('TallyPrime endpoint configured');
  ok('Company list configured');
  blank();
  console.log(chalk.white('  What comes next:'));
  dim('The pipeline code will be delivered to this directory.');
  dim('Once received, a single command will complete the installation.');
  blank();
  rule();
  blank();
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN
// ══════════════════════════════════════════════════════════════════════════════
(async () => {
  try {
    banner();

    const { proceed } = await ask({
      type: 'confirm', name: 'proceed',
      message: 'Ready to begin?',
      initial: true,
    });
    if (!proceed) {
      blank();
      console.log(chalk.yellow('  Aborted. Re-run when ready.'));
      process.exit(0);
    }

    await checkPython();
    const dir = await chooseDirectory();
    await writeEnvFile(dir);
    summary(dir);

  } catch (e) {
    // enquirer throws '' on Ctrl+C
    if (e === '' || e?.message === '') {
      blank();
      console.log(chalk.yellow('  Cancelled.'));
      process.exit(0);
    }
    console.error(chalk.red('\n  Unexpected error: ' + e.message));
    process.exit(1);
  }
})();
