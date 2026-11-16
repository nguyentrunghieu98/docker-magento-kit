# UI testing (Magento example)

The project facts the `ui-worker` role and the UI gate need: how a change reaches the browser, how
to open a page, and what a screenshot must prove. The loop itself is in the `ui-worker` role. The
rules for writing the view files are in the UI rules file the hook injects (`ui-conventions.md`).

## Served checkout

One checkout is served at a time. Run `bin/wt status` first: the page you open is that checkout.
Serve another with `bin/wt use <name>`, and ask the user before switching.

## Rebuild after a change

The application runs in developer mode: static files are links and are published on the first
request. Run the line for every kind of file you changed, then reload the page.

| Changed | Run | Why |
|---|---|---|
| `.phtml`, layout XML | `bin/magento cache:clean layout block_html full_page` | the layout and the rendered blocks are cached |
| UI component XML, `di.xml`, `view.xml` | `bin/magento cache:clean` | the merged configuration is cached |
| `.less` | `bin/cli rm -rf var/view_preprocessed/pub/static/<area>/<Vendor>/<theme> pub/static/<area>/<Vendor>/<theme>` | a published `.css` hides the `.less` behind it |
| `.less`, with Grunt set up | `bin/grunt less:<theme>` | compiles and prints the error with file and line |
| A new or renamed `.js`, `.html`, image | the same `rm` as for `.less` | only an existing file is linked, a new one is not published yet |
| `requirejs-config.js` | `bin/magento cache:clean`, then the same `rm` | the merged `requirejs-config.js` is a published file |
| `i18n/*.csv` | `bin/magento cache:clean translate`, then the same `rm` | dictionaries are cached, and the JS dictionary is a published file |

- `<area>` is `frontend` or `adminhtml`. Never delete `pub/static/.htaccess`.
- `bin/watch` does the `rm` on every change in `app/code` and `app/design`. With it running, only
  the cache lines are left to run.
- A compile error in LESS is in `var/log/system.log` and on the page. Read it before another try.
- `setup:static-content:deploy` is for a production build, not for this loop.

## Open a page

- Base URL: `https://magento.test/`, admin at `/admin/`.
- Browser tool: `<the command this project uses>`. It must set the window width, save a
  screenshot to a path and list the console messages.
- Admin login: user and password are in `env/magento.env`. Read them when needed. Never print them
  and never write them into a file.

```bash
<browser> open https://magento.test/customer/account/create
<browser> resize 390 844
<browser> screenshot --full-page --filename <plan>/evidence/03-1-390.png
<browser> console error
```

## Widths

| Width | Stands for |
|---|---|
| 390 | phone, below the 768 breakpoint |
| 1440 | desktop |

The admin is checked at 1440 only.

## A screenshot passes when

- It shows what the `ui:` requirement says, on the page and at the width it names.
- The page does not scroll sideways: `document.documentElement.scrollWidth` is not larger than
  `window.innerWidth`.
- The console has no error the page did not have before the change, and no request for a file of
  this change failed.
- It was taken after the last edit and after the rebuild.
