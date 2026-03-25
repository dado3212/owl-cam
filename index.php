<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Owl Cam — Alex Beals</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Crimson+Pro:ital,wght@0,300;0,400;0,600;1,300;1,400&display=swap');

  *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }

  body {
    background: #0f0e0d;
    color: #d4cfc4;
    font-family: 'Crimson Pro', Georgia, serif;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  header {
    padding: 2.5rem 1rem 1rem;
    text-align: center;
  }

  h1 {
    font-size: 1.8rem;
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: #b8a978;
  }

  .subtitle {
    font-style: italic;
    font-weight: 300;
    color: #6b6458;
    margin-top: 0.4rem;
    font-size: 1.05rem;
  }

  .stream-wrap {
    position: relative;
    width: min(95vw, 1280px);
    margin: 1.5rem auto;
    border: 1px solid #2a2722;
    border-radius: 3px;
    overflow: hidden;
    background: #0a0908;
  }

  .stream-wrap img {
    width: 100%;
    display: block;
  }

  .offline {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    color: #4a453c;
    height: calc(100vh - 300px);
  }

  .offline svg {
    width: 200px;
    height: 200px;
    margin-bottom: 1.5rem;
    opacity: 0.3;
  }

  .offline p {
    font-size: 1.3rem;
    font-style: italic;
    font-weight: 300;
  }

  .offline .sub {
    font-size: 0.9rem;
    margin-top: 0.5rem;
    color: #3a362f;
  }

  .status {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.4rem 0;
    font-size: 0.85rem;
    color: #6b6458;
  }

  .dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: #4a7c4a;
    animation: pulse 2.5s ease-in-out infinite;
  }

  .dot.off {
    background: #7c4a4a;
    animation: none;
  }

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }
</style>
</head>
<body>

<header>
  <h1>Owl Cam</h1>
  <p class="subtitle">Juvenile Great Horned Owl in <br />
    UNCA Asheville's Urban Forest</p>
</header>

<div class="stream-wrap" id="wrap">
</div>

<div class="status">
  <div class="dot <?php $live ? '' : 'off' ?>" id="dot"></div>
  <span id="statusText"><?php $live ? "Live — $clients watching" : 'Offline' ?></span>
</div>

<script>
const dot = document.getElementById('dot');
const text = document.getElementById('statusText');
const wrap = document.getElementById('wrap');
var isOffline = false;

function markOffline() {
  if (isOffline) return;
  isOffline = true;
  dot.classList.add('off');
  text.textContent = 'Offline';

  wrap.innerHTML = `
    <div class="offline" id="offlineMsg">
      <svg xmlns="http://www.w3.org/2000/svg" version="1.1" viewBox="-5.0 -10.0 110.0 135.0" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="m28.777 43.418c0.10547-0.75781 1.4727-3.3242 2.2461-3.3945 0.48437-0.042969 7.0977 4.832 8.0977 5.3789-1.6289 6.5469-11.281 4.8828-10.344-1.9844zm65.691-38.289c-5.5156 8.3125-14.43 12.391-22.879 17.027-7.0195-1.8906-14.305-2.8086-21.59-2.7969-7.2852-0.011719-14.57 0.90625-21.59 2.7969-8.4453-4.6367-17.363-8.7148-22.879-17.027-0.625 6.5195 1 13.852 5.9531 18.387l38.512 25.988 38.512-25.988c4.9531-4.5352 6.5781-11.867 5.9531-18.387zm-23.246 38.289c-0.10547-0.75781-1.4727-3.3242-2.2461-3.3945-0.48437-0.042969-7.0977 4.832-8.0977 5.3789 1.6289 6.5469 11.281 4.8828 10.344-1.9844zm0.73047-5.4336c9.6133 10.562-7.6875 22.18-14.051 9.4531l-4.125 2.7695 5.4727 7.1445-9.3203 16.109-9.1836-16.109 5.4727-7.1445-4.125-2.7695c-6.3633 12.727-23.664 1.1055-14.051-9.4531l-9.8711-6.4258c-7.7266 10.504-9.043 24.344-2.9766 35.988 7.0312 13.504 22.293 19.914 34.734 27.32 0.023437-0.011719 0.046874-0.027344 0.066406-0.039063 0.023437 0.011719 0.046875 0.027344 0.066406 0.039063 12.441-7.4023 27.703-13.812 34.734-27.32 6.0664-11.645 4.75-25.484-2.9766-35.988l-9.8711 6.4258z"/>
      </svg>
      <p>The owls are resting</p>
      <p class="sub">Stream is offline — check back soon</p>
    </div>`;
}

function checkStatus() {
  fetch('/projects/owl-cam/status')
    .then(r => r.json())
    .then(data => {

      if (data.live) {
        dot.classList.remove('off');
        var parts = [];
        var s = data.uptime;
        var d = Math.floor(s / 86400); s %= 86400;
        var h = Math.floor(s / 3600); s %= 3600;
        var m = Math.floor(s / 60);
        if (d > 0) parts.push(d + 'd');
        if (h > 0) parts.push(h + 'h');
        parts.push(m + 'm');
        var uptimeStr = parts.join(' ');
        text.textContent = 'Live — ' + data.clients + ' watching — uptime ' + uptimeStr;

        if (!document.getElementById('stream')) {
          wrap.innerHTML = '<img id="stream" src="/projects/owl-cam/stream" alt="Owl cam live stream">';
        }
      } else {
       markOffline();
      }
    })
    .catch(() => {
      markOffline();
    });
}

checkStatus();
setInterval(checkStatus, 5000);
</script>
</body>
</html>
