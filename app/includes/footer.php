</main>

<footer class="footer">
  <span><strong><?= e(APP_NAME) ?></strong> v<?= e(APP_VERSION) ?></span>
  <span>University of Education, Winneba &middot; MPhil ICT &middot; ICTE825</span>
  <span class="spacer"></span>
  <span><?= date('D, d M Y H:i') ?></span>
  <span>
    <?php
      try {
          echo 'MariaDB ' . e((string) Database::get()->scalar('SELECT VERSION()'));
      } catch (Throwable) {
          echo 'database offline';
      }
    ?>
    &middot; connected as <code class="inline"><?= e(DB_USER) ?></code>
  </span>
</footer>

</body>
</html>
