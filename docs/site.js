const macPanes = [
  {
    id: "displays",
    title: "Display Brightness",
    copy: "Per-panel brightness and contrast. One slider can keep each display’s mix. Optional menu bar extra.",
    shot: "screenshots/displays.png",
    demo: "brightness",
  },
  {
    id: "night-shift",
    title: "Night Shift",
    copy: "A 24-hour warmth curve for system Night Shift. Optional follow dims or brightens external monitors.",
    shot: "screenshots/night-shift.png",
    demo: "curve",
  },
  {
    id: "arrangement",
    title: "Display Arrangement",
    copy: "Save layout presets for the screens that are plugged in now. Keyboard shortcut plus a layout HUD.",
    shot: "screenshots/arrangement.png",
    demo: "layout",
  },
  {
    id: "sound",
    title: "Sound",
    copy: "Output volume, then a per-app mixer. Optional menu bar extra. Needs System Audio Recording for per-app volume.",
    shot: "screenshots/sound.png",
    demo: "mixer",
  },
  {
    id: "windows",
    title: "Window Management",
    copy: "Hold a chord to move or resize from anywhere. Throw, organize, shake-to-focus, Dock-click minimize.",
    shot: "screenshots/windows.png",
    demo: "throw",
  },
  {
    id: "dock-previews",
    title: "Dock Previews",
    copy: "Hover a Dock icon to see that app’s windows. Optional cards in the app switcher while Command-Tab is up.",
    shot: "screenshots/dock-previews.png",
    demo: "cards",
  },
  {
    id: "pointer",
    title: "Pointer & Scroll",
    copy: "Pointer speed, wheel and thumb-wheel speed, smooth scrolling, direction. Not gated on an MX Master.",
    shot: "screenshots/pointer.png",
    demo: "pointer",
  },
  {
    id: "system-monitor",
    title: "System Monitor",
    copy: "Optional second menu bar extra: live network speed plus CPU, GPU, memory, disk, sensors, and battery.",
    shot: "screenshots/system-monitor.png",
    demo: "spark",
  },
];

const devices = [
  {
    id: "dualsense",
    title: "DualSense / Edge",
    copy: "Buttons, sticks, rumble. 1-finger and 2-finger touchpad are separate Gestures. Sticks can be pointer or scroll.",
    demo: "dualsense",
  },
  {
    id: "siri",
    title: "Siri Remote",
    copy: "Clickpad pointer, click-wheel scroll, face buttons, live calibration. A2540.",
    demo: "siri",
  },
  {
    id: "mx3",
    title: "MX Master 3 / 3S",
    copy: "Extra buttons plus thumb Gesture — tap is a click, hold and move is a swipe.",
    demo: "swipe",
  },
  {
    id: "mx4",
    title: "MX Master 4",
    copy: "Extra buttons including Side, plus the Haptic pad. Isolated HID++ reader.",
    demo: "haptic",
  },
];

const demos = {
  brightness: `
    <div class="toy toy-brightness">
      <span class="sun"></span>
      <span class="track"><i></i></span>
    </div>`,
  curve: `
    <svg class="toy toy-curve" viewBox="0 0 200 72" aria-hidden="true">
      <path d="M8 58 C 40 58, 52 18, 92 22 S 150 62, 192 28" />
    </svg>`,
  layout: `
    <div class="toy toy-layout">
      <span class="panel a"></span>
      <span class="panel b"></span>
      <span class="panel c"></span>
    </div>`,
  mixer: `
    <div class="toy toy-mixer">
      <span><i></i></span><span><i></i></span><span><i></i></span>
    </div>`,
  throw: `
    <div class="toy toy-throw">
      <span class="cell"></span><span class="cell"></span><span class="cell"></span>
      <span class="cell"></span><span class="cell on"></span><span class="cell"></span>
      <span class="cell"></span><span class="cell"></span><span class="cell"></span>
      <span class="win"></span>
    </div>`,
  cards: `
    <div class="toy toy-cards">
      <span></span><span></span><span></span>
    </div>`,
  pointer: `
    <div class="toy toy-pointer">
      <span class="path"></span>
      <span class="dot"></span>
    </div>`,
  spark: `
    <svg class="toy toy-spark" viewBox="0 0 200 72" aria-hidden="true">
      <polyline points="8,50 28,42 48,46 68,28 88,34 108,18 128,26 148,14 168,22 192,10" />
    </svg>`,
  dualsense: `
    <div class="toy toy-pad">
      <span class="stick"></span>
      <span class="touch"></span>
      <span class="stick"></span>
    </div>`,
  siri: `
    <div class="toy toy-siri">
      <span class="clickpad"></span>
    </div>`,
  swipe: `
    <div class="toy toy-swipe">
      <span class="thumb"></span>
    </div>`,
  haptic: `
    <div class="toy toy-haptic">
      <span class="pad"></span>
    </div>`,
};

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

function chips(el, items, onPick) {
  el.replaceChildren(
    ...items.map((item, index) => {
      const button = document.createElement("button");
      button.type = "button";
      button.setAttribute("role", "tab");
      button.textContent = item.title;
      button.addEventListener("click", () => onPick(index, true));
      return button;
    })
  );
}

function markChip(el, index) {
  [...el.children].forEach((button, i) => {
    button.setAttribute("aria-selected", i === index ? "true" : "false");
  });
}

function playDemo(host, kind) {
  host.innerHTML = demos[kind] || "";
  host.dataset.kind = kind;
  host.classList.remove("is-on");
  void host.offsetWidth;
  host.classList.add("is-on");
}

function tour({ chipsEl, items, shotEl, titleEl, copyEl, demoEl, autoplay }) {
  let index = 0;
  let timer = 0;
  const wait = reduceMotion ? 0 : 7000;

  const show = (next, stop) => {
    index = (next + items.length) % items.length;
    const item = items[index];
    markChip(chipsEl, index);
    titleEl.textContent = item.title;
    copyEl.textContent = item.copy;
    if (shotEl && item.shot) {
      shotEl.classList.add("is-out");
      const apply = () => {
        shotEl.src = item.shot;
        shotEl.alt = item.title;
        shotEl.classList.remove("is-out");
      };
      if (reduceMotion) apply();
      else setTimeout(apply, 180);
    }
    playDemo(demoEl, item.demo);
    if (stop) pause();
    else arm();
  };

  const arm = () => {
    if (!autoplay || reduceMotion) return;
    clearTimeout(timer);
    timer = setTimeout(() => show(index + 1, false), wait);
  };

  const pause = () => {
    autoplay = false;
    clearTimeout(timer);
  };

  chips(chipsEl, items, show);
  show(0, false);
  return { show, pause, next: () => show(index + 1, true), prev: () => show(index - 1, true) };
}

const mac = tour({
  chipsEl: document.getElementById("mac-chips"),
  items: macPanes,
  shotEl: document.getElementById("shot"),
  titleEl: document.getElementById("intro-title"),
  copyEl: document.getElementById("intro-copy"),
  demoEl: document.getElementById("demo"),
  autoplay: true,
});

tour({
  chipsEl: document.getElementById("device-chips"),
  items: devices,
  shotEl: null,
  titleEl: document.getElementById("device-title"),
  copyEl: document.getElementById("device-copy"),
  demoEl: document.getElementById("device-demo"),
  autoplay: true,
});

document.addEventListener("keydown", (event) => {
  if (event.key === "ArrowRight") mac.next();
  if (event.key === "ArrowLeft") mac.prev();
});

const brew = document.getElementById("install");
brew.addEventListener("click", async () => {
  const text = brew.querySelector("code").textContent;
  const hint = brew.querySelector("[data-hint]");
  try {
    await navigator.clipboard.writeText(text);
    hint.textContent = "Copied";
  } catch {
    hint.textContent = "Select and copy";
  }
  setTimeout(() => {
    hint.textContent = "Copy";
  }, 1600);
});
