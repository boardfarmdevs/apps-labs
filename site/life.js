/*
 * The life of an application: shows one step of the list at a time, moves the figure with
 * it, and plays the steps in turn. Without this script the page lists every step and the
 * figure rests on "start".
 */
(() => {
  const figure = document.querySelector('.life');
  if (!figure) return;
  const steps = [...figure.querySelectorAll('.life-steps > li')];
  const controls = figure.querySelector('.life-controls');
  if (!steps.length || !controls) return;
  const still = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const pace = 4200;
  let current = Math.max(0, Number(figure.dataset.step || 1) - 1);
  let timer = null;

  // The framework the figure and the commands are for.
  const frameworks = [['dac', 'DAC'], ['lcm', 'LCM']].map(([name, label]) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'fw';
    button.textContent = label;
    button.addEventListener('click', () => { stop(); framework(name); });
    controls.append(button);
    return [name, button];
  });
  const gap = document.createElement('span');
  gap.className = 'gap';
  controls.append(gap);
  function framework(name) {
    figure.dataset.fw = name;
    frameworks.forEach(([other, button]) => button.setAttribute('aria-pressed', other === name ? 'true' : 'false'));
  }

  const buttons = steps.map((step, index) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = `${index + 1} ${step.dataset.name || ''}`.trim();
    button.addEventListener('click', () => { stop(); show(index); });
    controls.append(button);
    return button;
  });
  const play = document.createElement('button');
  play.type = 'button';
  play.className = 'play';
  controls.append(play);

  function show(index) {
    current = (index + steps.length) % steps.length;
    figure.dataset.step = String(current + 1);
    steps.forEach((step, i) => step.classList.toggle('current', i === current));
    buttons.forEach((button, i) => {
      if (i === current) button.setAttribute('aria-current', 'step');
      else button.removeAttribute('aria-current');
    });
  }
  function label() {
    play.textContent = timer ? 'Pause' : 'Play';
    play.setAttribute('aria-pressed', timer ? 'true' : 'false');
  }
  function stop() {
    if (timer) clearInterval(timer);
    timer = null;
    label();
  }
  function start() {
    stop();
    timer = setInterval(() => {
      // after the last step, the other framework's turn
      if (current === steps.length - 1) framework(figure.dataset.fw === 'dac' ? 'lcm' : 'dac');
      show(current + 1);
    }, pace);
    label();
  }
  play.addEventListener('click', () => (timer ? stop() : start()));

  figure.classList.add('scripted');
  framework(figure.dataset.fw === 'lcm' ? 'lcm' : 'dac');
  // A link can name a step: #life-5 opens on the fifth and does not play.
  const named = /^#life-(\d+)$/.exec(window.location.hash);
  const linked = named && Number(named[1]) >= 1 && Number(named[1]) <= steps.length;
  show(linked ? Number(named[1]) - 1 : still ? current : 0);
  label();
  // Play once the figure is in view, and only for those who have not asked for stillness.
  if (!still && !linked && 'IntersectionObserver' in window) {
    const seen = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) {
        seen.disconnect();
        start();
      }
    }, { threshold: 0.4 });
    seen.observe(figure.querySelector('svg'));
  }
})();
