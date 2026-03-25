<?php
// Fetch status from relay
$status = @file_get_contents('http://127.0.0.1:16146/status');
$live = false;
$clients = 0;
if ($status) {
    $data = json_decode($status, true);
    $live = $data['live'] ?? false;
    $clients = $data['clients'] ?? 0;
}
?>
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
    aspect-ratio: 16/9;
    color: #4a453c;
  }

  .offline svg {
    width: 64px;
    height: 64px;
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

  footer {
    margin-top: auto;
    padding: 2rem 1rem;
    text-align: center;
    font-size: 0.8rem;
    color: #3a362f;
  }

  footer a {
    color: #6b6458;
    text-decoration: none;
  }

  footer a:hover {
    color: #b8a978;
  }
</style>
</head>
<body>

<header>
  <h1>Owl Cam</h1>
  <p class="subtitle">A quiet watch</p>
</header>

<div class="stream-wrap" id="wrap">
<?php if ($live): ?>
  <img id="stream" src="/projects/owl-cam/stream" alt="Owl cam live stream">
<?php else: ?>
  <div class="offline" id="offlineMsg">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <path d="M12 3c-4.97 0-9 4.03-9 9s4.03 9 9 9 9-4.03 9-9-4.03-9-9-9z"/>
      <circle cx="9" cy="10" r="1.5" fill="currentColor" stroke="none"/>
      <circle cx="15" cy="10" r="1.5" fill="currentColor" stroke="none"/>
      <path d="M8 15c1.5 2 6.5 2 8 0" stroke-linecap="round"/>
    </svg>
    <p>The owls are resting</p>
    <p class="sub">Stream is offline — check back soon</p>
  </div>
<?php endif; ?>
</div>

<div class="status">
  <div class="dot <?= $live ? '' : 'off' ?>" id="dot"></div>
  <span id="statusText"><?= $live ? "Live — $clients watching" : 'Offline' ?></span>
</div>

<footer>
  <a href="/projects">alexbeals.com</a>
</footer>

<script>
function checkStatus() {
  fetch('/projects/owl-cam/status')
    .then(r => r.json())
    .then(data => {
      const dot = document.getElementById('dot');
      const text = document.getElementById('statusText');
      const wrap = document.getElementById('wrap');

      if (data.live) {
        dot.classList.remove('off');
        text.textContent = 'Live — ' + data.clients + ' watching';

        // If we were offline, add the stream img
        if (!document.getElementById('stream')) {
          wrap.innerHTML = '<img id="stream" src="/projects/owl-cam/stream" alt="Owl cam live stream">';
        }
      } else {
        dot.classList.add('off');
        text.textContent = 'Offline';

        // Show offline message if stream was showing
        if (document.getElementById('stream')) {
          wrap.innerHTML = `
            <div class="offline" id="offlineMsg">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                <path d="M12 3c-4.97 0-9 4.03-9 9s4.03 9 9 9 9-4.03 9-9-4.03-9-9-9z"/>
                <circle cx="9" cy="10" r="1.5" fill="currentColor" stroke="none"/>
                <circle cx="15" cy="10" r="1.5" fill="currentColor" stroke="none"/>
                <path d="M8 15c1.5 2 6.5 2 8 0" stroke-linecap="round"/>
              </svg>
              <p>The owls are resting</p>
              <p class="sub">Stream is offline — check back soon</p>
            </div>`;
        }
      }
    })
    .catch(() => {});
}

setInterval(checkStatus, 5000);
</script>
</body>
</html>
