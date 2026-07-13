<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="Explore assets issued on the Yerbas blockchain.">
  <title><?php echo htmlspecialchars($data['title'], ENT_QUOTES, 'UTF-8'); ?> | Yerbas Asset Explorer</title>
  <link rel="stylesheet" href="./theme/w3css/css/style.css">
  <link rel="stylesheet" href="./theme/w3css/css/explorer.css">
</head>
<body>
  <header class="site-header">
    <div class="container header-inner">
      <a class="brand" href="./" aria-label="Yerbas Asset Explorer home">
        <span class="brand-mark">Y</span>
        <span>
          <strong>Yerbas</strong>
          <small>Asset Explorer</small>
        </span>
      </a>

      <nav class="main-nav" aria-label="Primary navigation">
        <a href="./">Assets</a>
        <a href="https://explorer.yerbas.org/" target="_blank" rel="noopener">Blocks</a>
        <a href="https://yerbas.org/" target="_blank" rel="noopener">Yerbas.org</a>
        <a href="https://discord.gg/XGEp2cKSKF" target="_blank" rel="noopener">Discord</a>
      </nav>

      <button class="theme-toggle" type="button" id="themeToggle" aria-label="Toggle light and dark mode">◐</button>
    </div>
  </header>

  <main class="site-main">
    <div class="container">