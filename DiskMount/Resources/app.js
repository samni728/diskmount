(() => {
  const devicesElement = document.getElementById('devices');
  const dependencyElement = document.getElementById('dependency');
  const noticeElement = document.getElementById('notice');
  const versionElement = document.getElementById('version');
  const proButton = document.getElementById('pro-button');
  const proConfirm = document.getElementById('pro-confirm');
  let proMode = false;

  const send = (action, deviceID, extra = {}) => {
    if (!window.webkit?.messageHandlers?.bridge) return;
    window.webkit.messageHandlers.bridge.postMessage({ action, deviceID, ...extra });
  };

  const escapeHTML = (value) => String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');

  const formatBytes = (bytes) => {
    if (!Number(bytes)) return '未知容量';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1000)), units.length - 1);
    return `${(bytes / (1000 ** index)).toFixed(index > 2 ? 1 : 0)} ${units[index]}`;
  };

  const renderDevice = (device, busyID, dependencyAvailable) => {
    const busy = busyID === device.id;
    const status = device.mounted
      ? (device.writable ? '已加载 · 可写' : '已加载 · 只读')
      : '未加载';
    let primaryAction = '';
    if (!device.isProtected && device.isNTFS) {
      primaryAction = `<button class="action primary" data-action="mountNTFS" data-device="${escapeHTML(device.id)}" ${busy || !dependencyAvailable ? 'disabled' : ''}>${busy ? '处理中…' : 'NTFS 读写加载'}</button>`;
    } else if (!device.isProtected && !device.mounted) {
      primaryAction = `<button class="action primary" data-action="mount" data-device="${escapeHTML(device.id)}" ${busy ? 'disabled' : ''}>${busy ? '处理中…' : '加载'}</button>`;
    }

    const mountedActions = device.mounted && !device.isProtected
      ? `<button class="action" data-action="open" data-device="${escapeHTML(device.id)}" ${busy ? 'disabled' : ''}>在 Finder 打开</button>
         <button class="action" data-action="unmount" data-device="${escapeHTML(device.id)}" ${busy ? 'disabled' : ''}>卸载卷</button>`
      : '';

    const finalActions = device.isProtected
      ? '<div class="protected-note">系统或辅助分区 · 仅供查看，磁盘操作已锁定</div>'
      : `${primaryAction}${mountedActions}<button class="action danger" data-action="eject" data-device="${escapeHTML(device.id)}" ${busy ? 'disabled' : ''}>安全弹出整盘</button>`;

    return `<article class="device ${device.isProtected ? 'protected' : ''}">
      <div class="device-head">
        <div class="device-title">
          <h2>${escapeHTML(device.name)}</h2>
          <p>/dev/${escapeHTML(device.id)}</p>
        </div>
        <span class="badge">${escapeHTML(device.fileSystem || device.content || '未知格式')}</span>
      </div>
      <div class="meta">
        <span>状态 <strong>${status}</strong></span>
        <span>容量 <strong>${formatBytes(device.size)}</strong></span>
        <span>整盘 <strong>/dev/${escapeHTML(device.wholeDiskIdentifier)}</strong></span>
        <span>文件系统 <strong>${escapeHTML(device.fileSystem || device.content || '未知')}</strong></span>
        <span class="wide">挂载位置 <strong class="path">${escapeHTML(device.mountPoint || '尚未挂载')}</strong></span>
      </div>
      <div class="actions">
        ${finalActions}
      </div>
    </article>`;
  };

  window.DiskMount = {
    receive(state) {
      versionElement.textContent = state.version;
      proMode = Boolean(state.proMode);
      proButton.classList.toggle('active', proMode);
      proButton.textContent = proMode ? '专家模式 · 已开启' : '专家模式';
      proButton.title = proMode ? '退出专家模式' : '显示系统与高级分区';
      dependencyElement.innerHTML = state.dependency.available
        ? `<span class="dot"></span><span>NTFS 引擎可用 · ${escapeHTML(state.dependency.version || state.dependency.path)}</span>`
        : '<span class="dot missing"></span><span>未安装 anylinuxfs，NTFS 读写功能不可用</span>';

      if (state.error) {
        noticeElement.innerHTML = `<div class="notice error">${escapeHTML(state.error)}</div>`;
      } else if (state.message) {
        noticeElement.innerHTML = `<div class="notice success">${escapeHTML(state.message)}</div>`;
      } else {
        noticeElement.innerHTML = '';
      }

      devicesElement.innerHTML = state.devices.length
        ? state.devices.map(device => renderDevice(device, state.busyDeviceID, state.dependency.available)).join('')
        : '<div class="empty">没有检测到外接物理磁盘。<br>插入 U 盘或移动硬盘后点击刷新。</div>';
    }
  };

  document.addEventListener('click', (event) => {
    const button = event.target.closest('[data-action]');
    if (!button || button.disabled) return;
    const action = button.dataset.action;
    if (action === 'togglePro') {
      if (proMode) send('setProMode', undefined, { enabled: false });
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
    send(action, button.dataset.device);
  });

  send('ready');
})();
