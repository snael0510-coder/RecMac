(() => {
  'use strict';

  const korean = document.documentElement.lang === 'ko';
  const state = {
    phase: 'idle', mode: 'window', count: 3, seconds: 0, saved: 0,
    systemAudio: true, microphone: false, advanced: false, hover: false,
    showThanks: false
  };
  let timer = null;
  let later = null;

  function clearTimers() {
    if (timer) clearInterval(timer);
    if (later) clearTimeout(later);
    timer = later = null;
  }

  function formatTime(seconds) {
    return String(Math.floor(seconds / 60)).padStart(2, '0') + ':' +
           String(seconds % 60).padStart(2, '0');
  }

  function values() {
    const active = state.phase === 'count' || state.phase === 'rec';
    const selected = (mode) => state.mode === mode;
    const rects = {
      window: ['8%', '16%', '84%', '58%', '1.2em'],
      area: ['24%', '22%', '52%', '40%', '0.8em'],
      screen: ['0%', '0%', '100%', '100%', '2rem'],
      audio: ['50%', '50%', '0%', '0%', '0']
    };
    const r = rects[state.mode];
    let shadow = '0 0 0 0 rgba(0,0,0,0), inset 0 0 0 0 rgba(255,59,48,0)';
    if (active && state.mode !== 'screen' && state.mode !== 'audio') {
      shadow = '0 0 0 3000px rgba(0,0,0,0.55), 0 0 0 2px ' +
               (state.phase === 'rec' ? '#ff453a' : 'rgba(255,255,255,0.55)');
    }
    if (active && state.mode === 'screen') {
      shadow = 'inset 0 0 0 3px ' +
               (state.phase === 'rec' ? '#ff453a' : 'rgba(255,255,255,0.55)');
    }
    if (state.mode === 'audio') shadow = 'none';
    if (state.phase === 'idle') shadow = 'none';
    const modeColor = (mode) => selected(mode) ? '#ff3b30' : '#1d1d1f';
    const modeBackground = (mode) => selected(mode) ? 'rgba(0,0,0,0.11)' : 'transparent';
    const rec = state.phase === 'rec';
    const hover = rec && state.hover;
    return {
      accent: '#D70015',
      isIdle: state.phase === 'idle', isCount: state.phase === 'count',
      isRec: rec, isSaved: state.phase === 'saved',
      is1: state.phase === 'count' && state.count === 1,
      is2: state.phase === 'count' && state.count === 2,
      is3: state.phase === 'count' && state.count === 3,
      showThanks: state.showThanks,
      timeText: formatTime(state.seconds), savedText: formatTime(state.saved),
      waveLabel: rec ? (state.systemAudio
        ? (korean ? '맥 소리도 함께 녹화 중' : 'Recording the sound too')
        : (korean ? '맥 소리 없이 녹화 중' : 'Recording without Mac sound'))
        : '',
      waveLabelColor: rec && state.systemAudio ? '#ff6961' : '#ffffff',
      waveColor: rec && state.systemAudio ? '#ff453a' : 'rgba(255,255,255,0.8)',
      islandW: rec ? (hover ? '17em' : '15.5em') : (state.phase === 'saved' ? '13.5em' : '6.5em'),
      islandH: hover ? '4.2em' : '1.7em', islandR: hover ? '1.4em' : '0.8em',
      stopOpacity: hover ? '1' : '0', stopScale: hover ? '1' : '0.85',
      tbTransform: active ? 'translateY(140%) scale(0.92)' : 'none',
      tbOpacity: active ? '0' : '1', tbPointer: active ? 'none' : 'auto',
      dimL: r[0], dimT: r[1], dimW: r[2], dimH: r[3], dimR: r[4], dimShadow: shadow,
      areaBg: modeBackground('area'), screenBg: modeBackground('screen'),
      windowBg: modeBackground('window'), audioBg: modeBackground('audio'),
      areaStroke: modeColor('area'), screenStroke: modeColor('screen'),
      windowStroke: modeColor('window'), audioStroke: modeColor('audio'),
      pickAreaOn: String(selected('area')), pickScreenOn: String(selected('screen')),
      pickWindowOn: String(selected('window')), pickAudioOn: String(selected('audio')),
      sysOn: String(state.systemAudio), micOn: String(state.microphone),
      advOn: String(state.advanced),
      sysColor: state.systemAudio ? '#1d1d1f' : '#8e8e93',
      sysWaveOp: state.systemAudio ? '1' : '0', sysXOp: state.systemAudio ? '0' : '1',
      micColor: state.microphone ? '#1d1d1f' : '#8e8e93',
      micFill: state.microphone ? '#1d1d1f' : 'none',
      micSlashOp: state.microphone ? '0' : '1',
      advBg: state.advanced ? 'rgba(0,0,0,0.11)' : 'transparent',
      advStroke: state.advanced ? '#1d1d1f' : '#8e8e93'
    };
  }

  function render() {
    const v = values();
    document.querySelectorAll('[data-if]').forEach(el => { el.hidden = !v[el.dataset.if]; });
    document.querySelectorAll('[data-text]').forEach(el => { el.textContent = v[el.dataset.text] ?? ''; });
    document.querySelectorAll('[data-bind-style], [data-bind-aria-pressed], [data-bind-fill], [data-bind-stroke], [data-bind-opacity]').forEach(el => {
      for (const [name, template] of Object.entries(el.dataset)) {
        if (!name.startsWith('bind')) continue;
        const attr = name.slice(4).replace(/[A-Z]/g, c => '-' + c.toLowerCase()).replace(/^-/, '');
        const value = template.replace(/\[\[\s*(\w+)\s*\]\]/g, (_, key) => v[key] ?? '');
        el.setAttribute(attr, value);
      }
    });
  }

  const actions = {
    pickArea: () => { if (state.phase === 'idle') state.mode = 'area'; },
    pickScreen: () => { if (state.phase === 'idle') state.mode = 'screen'; },
    pickWindow: () => { if (state.phase === 'idle') state.mode = 'window'; },
    pickAudio: () => { if (state.phase === 'idle') state.mode = 'audio'; },
    toggleSys: () => { state.systemAudio = !state.systemAudio; },
    toggleMic: () => { state.microphone = !state.microphone; },
    toggleAdv: () => { state.advanced = !state.advanced; },
    hoverOn: () => { if (state.phase === 'rec') state.hover = true; },
    hoverOff: () => { state.hover = false; },
    thanks: () => { state.showThanks = true; },
    closeThanks: () => { state.showThanks = false; },
    start: () => {
      if (state.phase !== 'idle') return;
      clearTimers();
      state.phase = 'count'; state.count = 3;
      timer = setInterval(() => {
        if (state.count > 1) state.count--;
        else {
          clearInterval(timer);
          state.phase = 'rec'; state.seconds = 0;
          timer = setInterval(() => { state.seconds++; render(); }, 1000);
        }
        render();
      }, 1000);
    },
    stop: () => {
      if (state.phase !== 'rec') return;
      clearTimers();
      state.phase = 'saved'; state.saved = state.seconds; state.hover = false;
      later = setTimeout(() => { state.phase = 'idle'; render(); }, 2800);
    }
  };

  function run(name) {
    if (actions[name]) { actions[name](); render(); }
  }
  document.querySelectorAll('[data-action]').forEach(el => {
    el.addEventListener('click', () => run(el.dataset.action));
  });
  for (const [attribute, event] of [['data-mouseenter', 'mouseenter'],
                                     ['data-mouseleave', 'mouseleave'], ['data-focus', 'focus']]) {
    document.querySelectorAll('[' + attribute + ']').forEach(el => {
      el.addEventListener(event, () => run(el.getAttribute(attribute)));
    });
  }
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && state.showThanks) { state.showThanks = false; render(); }
  });
  document.querySelector('[data-if="showThanks"]')?.addEventListener('click', event => {
    if (event.target === event.currentTarget) { state.showThanks = false; render(); }
  });

  if (!korean && navigator.language?.toLowerCase().startsWith('ko')) {
    const hint = document.createElement('div');
    hint.style.cssText = 'text-align:center;padding:.65rem 1rem;background:#f5f5f7;font:500 .875rem Pretendard,system-ui,sans-serif';
    hint.innerHTML = '한국어 페이지가 있습니다. <a href="ko/">한국어로 보기 →</a>';
    document.querySelector('header')?.after(hint);
  }
  render();
})();
