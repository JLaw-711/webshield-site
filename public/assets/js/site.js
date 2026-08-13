/* WebShield marketing site — the only three interactive things on the page.
   Written as plain ES2019 with no build step and no dependencies: the site is
   four static files, and adding a toolchain to toggle a price would be the
   tail wagging the dog. Everything below degrades to working HTML if this
   file fails to load — the nav links are anchors, the prices render as
   monthly, and the form falls back to nothing rather than to something
   broken. */
(function () {
  'use strict';

  /* ---- mobile nav ------------------------------------------------------ */
  var toggle = document.querySelector('[data-nav-toggle]');
  var links = document.getElementById('nav-links');

  if (toggle && links) {
    toggle.addEventListener('click', function () {
      var open = links.classList.toggle('is-open');
      toggle.setAttribute('aria-expanded', String(open));
    });
    // Tapping a link should close the sheet, or the destination is hidden
    // behind the menu that took you there.
    links.addEventListener('click', function (event) {
      if (event.target.closest('a')) {
        links.classList.remove('is-open');
        toggle.setAttribute('aria-expanded', 'false');
      }
    });
  }

  /* ---- monthly / annual pricing ---------------------------------------
     Annual figures are the settled ladder (PROJECT.md §8): R299/R399/R499,
     which is ~15% off twelve monthly payments. R299 is deliberate charm
     pricing, not a rounding slip — don't "fix" it to R295.
     -------------------------------------------------------------------- */
  var PRICES = {
    monthly: { basic: 'R29', advanced: 'R39', premium: 'R49', per: '/month' },
    annual: { basic: 'R299', advanced: 'R399', premium: 'R499', per: '/year' }
  };

  var segments = document.querySelectorAll('[data-billing]');

  function setBilling(period) {
    var price = PRICES[period];
    if (!price) return;

    setText('[data-price-basic]', price.basic);
    setText('[data-price-advanced]', price.advanced);
    setText('[data-price-premium]', price.premium);

    var pers = document.querySelectorAll('[data-per]');
    for (var i = 0; i < pers.length; i++) pers[i].textContent = price.per;

    for (var j = 0; j < segments.length; j++) {
      segments[j].setAttribute(
        'aria-selected',
        String(segments[j].getAttribute('data-billing') === period)
      );
    }
  }

  function setText(selector, value) {
    var node = document.querySelector(selector);
    if (node) node.textContent = value;
  }

  for (var s = 0; s < segments.length; s++) {
    segments[s].addEventListener('click', function () {
      setBilling(this.getAttribute('data-billing'));
    });
  }

  /* ---- early-access signup --------------------------------------------
     Posts to the account service at api.webshield.online. The endpoint is
     deliberately dumb: it stores an address and a timestamp so we can send
     exactly one launch email. Failure is reported honestly rather than
     swallowed — a form that says "thanks!" and dropped the address is the
     small dishonesty this whole page is trying not to commit.
     -------------------------------------------------------------------- */
  var ENDPOINT = 'https://api.webshield.online/api/v1/notify';

  var form = document.querySelector('[data-notify-form]');
  var result = document.querySelector('[data-notify-result]');

  if (form && result) {
    var input = form.querySelector('input[type="email"]');
    var button = form.querySelector('button');

    form.addEventListener('submit', function (event) {
      event.preventDefault();
      var email = (input.value || '').trim();

      // A deliberately loose check. Address validity is the server's job;
      // this only catches the empty box and the missing @.
      if (email.length < 6 || email.indexOf('@') < 1) {
        say('That doesn’t look like an email address — could you check it?', true);
        input.focus();
        return;
      }

      button.disabled = true;
      button.textContent = 'Sending…';

      fetch(ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: email, source: 'website' })
      })
        .then(function (response) {
          if (response.ok) return response.json().catch(function () { return {}; });
          if (response.status === 429) throw new Error('rate');
          throw new Error('http ' + response.status);
        })
        .then(function () {
          form.style.display = 'none';
          say('✓ You’re on the list — we’ll email you the day WebShield launches.', false);
        })
        .catch(function (error) {
          button.disabled = false;
          button.textContent = 'Notify me';
          if (String(error.message) === 'rate') {
            say('That’s a few tries in a row. Give it a minute and try again.', true);
          } else {
            say(
              'We couldn’t save that just now. Please try again, or email ' +
                'support@webshield.online and we’ll add you by hand.',
              true
            );
          }
        });
    });
  }

  function say(message, isError) {
    result.textContent = message;
    result.classList.add('is-shown');
    result.classList.toggle('is-error', !!isError);
  }
})();
