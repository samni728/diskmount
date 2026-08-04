(() => {
  const strings = {
    en: {
      eyebrow: 'DISK CONTROL',
      expertMode: 'Expert Mode',
      expertModeOn: 'Expert Mode · On',
      expertShowTitle: 'Show system and advanced partitions',
      expertHideTitle: 'Exit Expert Mode',
      expertConfirmTitle: 'Enable Expert Mode?',
      expertConfirmBody: 'Recommended only for users familiar with macOS disk structures. Advanced volumes remain locked until separately authorized.',
      cancel: 'Cancel',
      enableExpert: 'I understand, enable Expert Mode',
      loading: 'Reading external disks…',
      star: '☆ Give us a Star',
      safeFooter: 'Safe external data volumes only by default',
      quit: 'Quit DiskMount',
      refresh: 'Refresh',
      switchLanguage: 'Switch to Chinese',
      languageButton: '中文',
      engineAvailable: 'NTFS engine available',
      engineMissing: 'NTFS runtime unavailable. Read/write mounting is disabled.',
      bundled: 'Bundled with app',
      development: 'Development environment',
      mountedWritable: 'Mounted · Writable',
      mountedReadOnly: 'Mounted · Read-only',
      notMounted: 'Not mounted',
      unknownCapacity: 'Unknown capacity',
      unknownFormat: 'Unknown format',
      unknown: 'Unknown',
      status: 'Status',
      capacity: 'Capacity',
      wholeDisk: 'Whole disk',
      fileSystem: 'File system',
      mountPoint: 'Mount point',
      noMountPoint: 'Not mounted',
      processing: 'Working…',
      mountNTFS: 'Mount NTFS Read/Write',
      ntfsWritable: 'NTFS Writable',
      autoReadWriteOn: 'Auto Read/Write: On',
      autoReadWriteOff: 'Auto Read/Write: Off',
      mount: 'Mount',
      openFinder: 'Open in Finder',
      eject: 'Safely Eject',
      protected: 'System or auxiliary partition · Per-volume authorization required',
      advancedUnlocked: 'Advanced access unlocked for this session · Whole-disk eject remains blocked',
      unlockAdvanced: 'Request Read/Write Access',
      mountAdvanced: 'Mount Advanced Volume',
      unmountAdvanced: 'Unmount Advanced Volume',
      securityWarning: 'SECURITY WARNING',
      advancedConfirmTitle: 'Unlock this advanced volume?',
      advancedConfirmBody: 'This can expose or modify EFI and system-related files. Back up important data first. Access applies only to this volume for the current app session.',
      advancedConfirmLimit: 'DiskMount will not bypass SIP, change disk format, or force a sealed macOS system volume to become writable.',
      confirmAdvanced: 'I understand, unlock this volume',
      empty: 'No external physical disk detected.',
      emptyHint: 'Insert a USB drive or external disk, then refresh.',
      openPrivacySettings: 'Open Privacy Settings',
      privacyHint: 'Enable Full Disk Access and Removable Volumes access for DiskMount, fully quit and reopen it, then try again.',
      updateAvailable: 'Version {version} is available · Click to download',
      openGitHub: 'Open GitHub project',
      buyCoffee: 'Buy me a coffee'
    },
    zh: {
      eyebrow: '磁盘控制',
      expertMode: '专家模式',
      expertModeOn: '专家模式 · 已开启',
      expertShowTitle: '显示系统与高级分区',
      expertHideTitle: '退出专家模式',
      expertConfirmTitle: '启用专家模式？',
      expertConfirmBody: '仅建议熟悉 macOS 磁盘结构的用户开启。高级卷仍会锁定，必须对单个卷再次授权。',
      cancel: '取消',
      enableExpert: '我了解风险，进入专家模式',
      loading: '正在读取外接磁盘…',
      star: '☆ 给我一个 Star',
      safeFooter: '默认仅显示安全的外接数据卷',
      quit: '退出 DiskMount',
      refresh: '刷新',
      switchLanguage: 'Switch to English',
      languageButton: 'EN',
      engineAvailable: 'NTFS 引擎可用',
      engineMissing: 'NTFS 运行时不可用，读写加载已禁用。',
      bundled: 'App 内嵌',
      development: '开发环境',
      mountedWritable: '已加载 · 可写',
      mountedReadOnly: '已加载 · 只读',
      notMounted: '未加载',
      unknownCapacity: '未知容量',
      unknownFormat: '未知格式',
      unknown: '未知',
      status: '状态',
      capacity: '容量',
      wholeDisk: '整盘',
      fileSystem: '文件系统',
      mountPoint: '挂载位置',
      noMountPoint: '尚未挂载',
      processing: '处理中…',
      mountNTFS: 'NTFS 读写加载',
      ntfsWritable: 'NTFS 可写',
      autoReadWriteOn: '自动读写：已开启',
      autoReadWriteOff: '自动读写：未开启',
      mount: '加载',
      openFinder: '在 Finder 打开',
      eject: '安全弹出',
      protected: '系统或辅助分区 · 需要对单个卷再次授权',
      advancedUnlocked: '本次会话已解锁高级访问 · 仍禁止弹出受保护整盘',
      unlockAdvanced: '申请读写访问',
      mountAdvanced: '加载高级卷',
      unmountAdvanced: '卸载高级卷',
      securityWarning: '系统安全警告',
      advancedConfirmTitle: '解锁这个高级卷？',
      advancedConfirmBody: '此操作可能暴露或修改 EFI 与系统相关文件。请先备份重要数据。授权仅适用于本次 App 会话的该卷。',
      advancedConfirmLimit: 'DiskMount 不会绕过 SIP、改变磁盘格式，也不会强制将已封存的 macOS 系统卷变为可写。',
      confirmAdvanced: '我了解风险，解锁该卷',
      empty: '没有检测到外接物理磁盘。',
      emptyHint: '插入 U 盘或移动硬盘后点击刷新。',
      openPrivacySettings: '打开隐私设置',
      privacyHint: '请为 DiskMount 开启“完全磁盘访问权限”和“可移动卷”权限，完全退出并重新打开后再试。',
      updateAvailable: '发现新版本 {version} · 点击前往下载',
      openGitHub: '打开 GitHub 项目',
      buyCoffee: '请我喝杯咖啡'
    }
  };

  const devicesElement = document.getElementById('devices');
  const dependencyElement = document.getElementById('dependency');
  const noticeElement = document.getElementById('notice');
  const versionElement = document.getElementById('version');
  const versionButton = document.getElementById('version-button');
  const updateIndicator = document.getElementById('update-indicator');
  const githubButton = document.getElementById('github-button');
  const coffeeButton = document.getElementById('coffee-button');
  const languageButton = document.getElementById('language-button');
  const proButton = document.getElementById('pro-button');
  const proConfirm = document.getElementById('pro-confirm');
  const protectedConfirm = document.getElementById('protected-confirm');
  const protectedDeviceName = document.getElementById('protected-device-name');
  const refreshButton = document.getElementById('refresh-button');
  const savedLanguage = (() => {
    try { return window.localStorage.getItem('language'); } catch (_) { return null; }
  })();
  let language = savedLanguage === 'zh' || savedLanguage === 'en'
    ? savedLanguage
    : (navigator.language.toLowerCase().startsWith('zh') ? 'zh' : 'en');
  let proMode = false;
  let latestState = null;
  let pendingProtectedDeviceID = null;

  const t = (key) => strings[language][key] ?? strings.en[key] ?? key;

  const send = (action, deviceID, extra = {}) => {
    if (!window.webkit?.messageHandlers?.bridge) return;
    window.webkit.messageHandlers.bridge.postMessage({ action, deviceID, language, ...extra });
  };

  const escapeHTML = (value) => String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');

  const formatBytes = (bytes) => {
    if (!Number(bytes)) return t('unknownCapacity');
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1000)), units.length - 1);
    const value = bytes / (1000 ** index);
    const formatted = new Intl.NumberFormat(language === 'zh' ? 'zh-CN' : 'en-US', {
      maximumFractionDigits: index > 2 ? 1 : 0
    }).format(value);
    return `${formatted} ${units[index]}`;
  };

  const applyLanguage = () => {
    document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
    document.querySelectorAll('[data-i18n]').forEach((element) => {
      element.textContent = t(element.dataset.i18n);
    });
    languageButton.textContent = t('languageButton');
    languageButton.title = t('switchLanguage');
    refreshButton.title = t('refresh');
    refreshButton.setAttribute('aria-label', t('refresh'));
    proButton.textContent = proMode ? t('expertModeOn') : t('expertMode');
    proButton.title = proMode ? t('expertHideTitle') : t('expertShowTitle');
    githubButton.title = t('openGitHub');
    githubButton.setAttribute('aria-label', t('openGitHub'));
    coffeeButton.title = t('buyCoffee');
    coffeeButton.setAttribute('aria-label', t('buyCoffee'));
    if (latestState) renderUpdateState(latestState.update);
  };

  const renderUpdateState = (update) => {
    const available = Boolean(update?.available && update?.latestVersion);
    const tooltip = available
      ? t('updateAvailable').replace('{version}', update.latestVersion)
      : '';
    versionButton.disabled = !available;
    versionButton.classList.toggle('has-update', available);
    updateIndicator.classList.toggle('hidden', !available);
    versionButton.dataset.tooltip = tooltip;
    versionButton.title = tooltip;
    versionButton.setAttribute('aria-label', tooltip || `DiskMount ${versionElement.textContent}`);
  };

  const renderDevice = (device, busyID, dependencyAvailable, advancedAuthorized, autoMountEnabled) => {
    const busy = busyID === device.id;
    const status = device.mounted
      ? (device.writable ? t('mountedWritable') : t('mountedReadOnly'))
      : t('notMounted');
    const fileSystem = device.fileSystem || device.content || t('unknown');
    let primaryAction = '';
    if (!device.isProtected && device.isNTFS && device.mounted && device.writable) {
      primaryAction = `<button class="action writable-state" disabled>${t('ntfsWritable')}</button>`;
    } else if (!device.isProtected && device.isNTFS) {
      primaryAction = `<button class="action primary" data-action="mountNTFS" data-device="${escapeHTML(device.id)}" ${busy || !dependencyAvailable ? 'disabled' : ''}>${busy ? t('processing') : t('mountNTFS')}</button>`;
    } else if (!device.isProtected && !device.mounted) {
      primaryAction = `<button class="action primary" data-action="mount" data-device="${escapeHTML(device.id)}" ${busy ? 'disabled' : ''}>${busy ? t('processing') : t('mount')}</button>`;
    }

    const mountedActions = device.mounted && !device.isProtected
      ? `<button class="action" data-action="open" data-device="${escapeHTML(device.id)}" ${busy ? 'disabled' : ''}>${t('openFinder')}</button>`
      : '';

    const autoMountAction = device.isNTFS && !device.isProtected
      ? `<button class="action auto-toggle ${autoMountEnabled ? 'active' : ''}" data-action="setAutoMountNTFS" data-enabled="${autoMountEnabled ? 'false' : 'true'}" data-device="${escapeHTML(device.id)}" ${busy ? 'disabled' : ''}>${autoMountEnabled ? t('autoReadWriteOn') : t('autoReadWriteOff')}</button>`
      : '';

    let finalActions;
    if (device.isProtected && !advancedAuthorized) {
      finalActions = `<div class="protected-note">${t('protected')}</div>
        <button class="action danger" data-action="requestProtectedAccess" data-device="${escapeHTML(device.id)}">${t('unlockAdvanced')}</button>`;
    } else if (device.isProtected) {
      const advancedActions = device.mounted
        ? `<button class="action" data-action="open" data-device="${escapeHTML(device.id)}" ${busy ? 'disabled' : ''}>${t('openFinder')}</button>
           <button class="action" data-action="unmountProtected" data-device="${escapeHTML(device.id)}" ${busy ? 'disabled' : ''}>${t('unmountAdvanced')}</button>`
        : `<button class="action primary" data-action="mountProtected" data-device="${escapeHTML(device.id)}" ${busy ? 'disabled' : ''}>${busy ? t('processing') : t('mountAdvanced')}</button>`;
      finalActions = `<div class="protected-note">${t('advancedUnlocked')}</div>${advancedActions}`;
    } else {
      finalActions = `${primaryAction}${mountedActions}${autoMountAction}<button class="action danger" data-action="eject" data-device="${escapeHTML(device.id)}" ${busy ? 'disabled' : ''}>${t('eject')}</button>`;
    }

    return `<article class="device ${device.isProtected ? 'protected' : ''}">
      <div class="device-head">
        <div class="device-title">
          <h2>${escapeHTML(device.name)}</h2>
          <p>/dev/${escapeHTML(device.id)}</p>
        </div>
        <span class="badge">${escapeHTML(fileSystem || t('unknownFormat'))}</span>
      </div>
      <div class="meta">
        <span>${t('status')} <strong>${status}</strong></span>
        <span>${t('capacity')} <strong>${formatBytes(device.size)}</strong></span>
        <span>${t('wholeDisk')} <strong>/dev/${escapeHTML(device.wholeDiskIdentifier)}</strong></span>
        <span>${t('fileSystem')} <strong>${escapeHTML(fileSystem)}</strong></span>
        <span class="wide">${t('mountPoint')} <strong class="path">${escapeHTML(device.mountPoint || t('noMountPoint'))}</strong></span>
      </div>
      <div class="actions">${finalActions}</div>
    </article>`;
  };

  const renderState = (state) => {
    versionElement.textContent = state.version;
    proMode = Boolean(state.proMode);
    proButton.classList.toggle('active', proMode);
    applyLanguage();
    renderUpdateState(state.update);

    dependencyElement.innerHTML = state.dependency.available
      ? `<span class="dot"></span><span>${t('engineAvailable')} · ${escapeHTML(state.dependency.version || state.dependency.path)} · ${state.dependency.bundled ? t('bundled') : t('development')}</span>`
      : `<span class="dot missing"></span><span>${t('engineMissing')}</span>`;

    if (state.error) {
      const permissionAction = state.removableVolumePermissionRequired
        ? `<div class="permission-actions"><span>${t('privacyHint')}</span><button class="action privacy-button" data-action="openPrivacySettings">${t('openPrivacySettings')}</button></div>`
        : '';
      noticeElement.innerHTML = `<div class="notice error">${escapeHTML(state.error)}${permissionAction}</div>`;
    } else if (state.message) {
      noticeElement.innerHTML = `<div class="notice success">${escapeHTML(state.message)}</div>`;
    } else {
      noticeElement.innerHTML = '';
    }

    const authorizedDevices = new Set(state.authorizedProtectedDeviceIDs || []);
    const autoMountDevices = new Set(state.autoMountNTFSPersistentIDs || []);
    devicesElement.innerHTML = state.devices.length
      ? state.devices.map(device => renderDevice(device, state.busyDeviceID, state.dependency.available, authorizedDevices.has(device.id), autoMountDevices.has(device.persistentID))).join('')
      : `<div class="empty">${t('empty')}<br>${t('emptyHint')}</div>`;
  };

  window.DiskMount = {
    receive(state) {
      latestState = state;
      if (state.language === 'zh' || state.language === 'en') language = state.language;
      renderState(state);
    }
  };

  document.addEventListener('click', (event) => {
    const button = event.target.closest('[data-action]');
    if (!button || button.disabled) return;
    const action = button.dataset.action;
    if (action === 'toggleLanguage') {
      language = language === 'en' ? 'zh' : 'en';
      try { window.localStorage.setItem('language', language); } catch (_) {}
      applyLanguage();
      if (latestState) renderState(latestState);
      send('setLanguage');
      return;
    }
    if (action === 'togglePro') {
      if (proMode) {
        protectedConfirm.classList.add('hidden');
        pendingProtectedDeviceID = null;
        send('setProMode', undefined, { enabled: false });
      }
      else proConfirm.classList.remove('hidden');
      return;
    }
    if (action === 'cancelPro') {
      proConfirm.classList.add('hidden');
      return;
    }
    if (action === 'enablePro') {
      proConfirm.classList.add('hidden');
      send('setProMode', undefined, { enabled: true });
      return;
    }
    if (action === 'requestProtectedAccess') {
      const device = latestState?.devices?.find(item => item.id === button.dataset.device);
      if (!device) return;
      pendingProtectedDeviceID = device.id;
      protectedDeviceName.textContent = `${device.name} · /dev/${device.id}`;
      protectedConfirm.classList.remove('hidden');
      return;
    }
    if (action === 'cancelProtectedAccess') {
      protectedConfirm.classList.add('hidden');
      pendingProtectedDeviceID = null;
      return;
    }
    if (action === 'confirmProtectedAccess') {
      if (pendingProtectedDeviceID) send('authorizeProtected', pendingProtectedDeviceID);
      protectedConfirm.classList.add('hidden');
      pendingProtectedDeviceID = null;
      return;
    }
    if (action === 'setAutoMountNTFS') {
      send(action, button.dataset.device, { enabled: button.dataset.enabled === 'true' });
      return;
    }
    send(action, button.dataset.device);
  });

  applyLanguage();
  send('ready');
})();
