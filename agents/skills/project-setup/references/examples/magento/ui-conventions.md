# UI rules (Magento example)

The hook `ui-conventions.sh` injects this file the first time an agent edits a view file. It holds
the platform rules, taken from the Adobe Commerce frontend documentation. Add the project's own
design rules at the end: theme, class prefix, widths, what the design forbids. Keep it short, every
line is read on each first UI edit.

## Extend before you override

- Never edit a file of Magento, of a parent theme or of another vendor, in `vendor/`, `lib/web` or
  `app/code`. A change lives in the project's module or theme.
- Layout: add a file with the same handle name in `layout/` that holds only the changed
  instructions. It is merged. A full replacement goes in `layout/override/base/` (module layout) or
  `layout/override/theme/<Vendor>/<theme>/` (parent theme), and only when merging cannot do it.
- Move, hide or wrap a block with `<move>`, `<referenceBlock>` and `<referenceContainer>` before
  copying a template. Remove with `remove="true"`. `<remove src>` only drops a file from `<head>`.
- Never use `<action>` in layout (deprecated): pass `<argument>` to the block.
- Template override: `<theme>/<Vendor>_<Module>/templates/<same relative path>`. A renamed copy
  replaces nothing.
- Styles: add rules in `_extend.less` of the theme (`web/css/source/`) or of the theme's module
  directory. Styles of a project module go in `view/<area>/web/css/source/_module.less`. Never
  copy a parent `.less` file to change a few rules.
- JavaScript: extend with a mixin under `config.mixins` in `requirejs-config.js` of the same area.
  Replace a whole module with `map` only when a mixin cannot do it.
- Wording: change it in `i18n/<locale>.csv`, not by overriding a template.

## Templates

- A `.phtml` renders what its block or view model gives it. No object creation, no query, no
  business logic.
- Escape every dynamic value for where it lands: `escapeHtml` in text, `escapeHtmlAttr` in an
  attribute, `escapeUrl` in a URL, `escapeJs` in a script string. No `@noEscape` on a value that
  comes from a user or a request.
- Every visible string is `__('literal')`. A variable inside `__()` is not collected: use `%1`.
- Never set `cacheable="false"` on a block of a catalog, product or CMS page: it makes the whole
  page uncacheable. Customer data comes from `customer-data` sections (`sections.xml`).
- Include a stylesheet or a script through layout or `requirejs-config.js`, never with a `<link>`
  or an inline `<script>` in the template.

## Styles

- Use the variables and mixins of the UI library (`lib/web/css/source/lib`) before a literal color
  or size.
- Width-specific rules go inside `.media-width(@extremum, @break)`, common rules inside
  `& when (@media-common = true)`. A raw `@media` query lands in both `styles-m.css` and
  `styles-l.css`.
- `_theme.less` replaces the parent's file, it is not merged: copy the variables you still need.
- `//@magento_import` stays commented with two slashes and only in a root source file.

## JavaScript

- Every script is an AMD module, addressed by its RequireJS id (`Vendor_Module/js/file`), never by
  a file path.
- Start a component with `data-mage-init` on its element, or `<script type="text/x-magento-init">`
  with a selector. No inline JavaScript. After inserting HTML that carries these, trigger
  `contentUpdated` on it.
- Confirm with `Magento_Ui/js/modal/confirm`, tell with `Magento_Ui/js/modal/alert`, open a popup
  with `Magento_Ui/js/modal/modal`, block the page during a request with the `loader` widget.
  Never `alert()`, `confirm()` or an outside popup library.
- Validate a form with `mage/validation`. A new rule is `$.validator.addMethod` in a mixin of
  `mage/validation`.
- A custom jQuery widget is named `<namespace>.<name>`. On the storefront depend on
  `jquery-ui-modules/<part>`, not on `jquery/ui`.
- Strings in `.js` are `$t('literal')` or `$.mage.__('literal')` with `mage/translate` required.
  In a Knockout template use the `i18n` binding.
- No top-level `deps` in `requirejs-config.js` unless the module must load on every page. A script
  that is not AMD needs a `shim`.
- Build DOM from data with text bindings. The Knockout `html` binding and jQuery `.html()` are
  HTML sinks: only for trusted markup.

## UI components

- Admin grids and forms are UI components: `view/adminhtml/ui_component/<name>.xml`, included with
  `<uiComponent name="<name>"/>` in layout. The file name is global: a file with the same name in
  another module is merged into it, which is how an existing grid or form is extended.
- On the storefront a UI component is configured in layout through the `jsLayout` argument, and
  its styles are written by hand.
- Options the XSD describes go in `<settings>`. `<argument name="data">` is only for the rest. To
  beat an existing node still written as `<argument>`/`<item>`, keep that shape: on merge it wins
  over `<settings>`.
- A field that depends on data or on the entity type comes from a modifier (`modifyMeta`,
  `modifyData`) in the data provider's pool, not from static XML.
- The data source is `<name>_data_source`, and `provider` is its full registry path
  `<name>.<name>_data_source`. A form uses `Magento_Ui/js/form/provider`, a grid
  `Magento_Ui/js/grid/provider`.
- A component with no children extends `uiElement`, one with children `uiCollection`. An overridden
  `initialize` or `initObservable` calls `this._super()` and returns `this`.
- Connect components with `imports`, `exports`, `links` and `listens`, not with global variables
  or DOM lookups. Only an observable property keeps updating. In `listens` the key is the outside
  path and the value the local method, the reverse of the other three.
- A modal button acts through `targetName` (the modal's registry name) and `actionName`
  (`openModal`, `closeModal`, `actionDone`, `actionCancel`).
- Names are cross-referenced by string: a typo fails silently. After a change, check the component
  in the browser with `require('uiRegistry').get('<full name>')`.
- Set `__disableTmpl` on data a user can type, so `${ }` in it is not evaluated.

## Before you say it works

Rebuild with the commands in the project's `ui-testing.md`, then look at the page at each width.
Reading the code is not a check.

Source: <https://developer.adobe.com/commerce/frontend-core/guide/>,
<https://developer.adobe.com/commerce/frontend-core/javascript/>,
<https://developer.adobe.com/commerce/frontend-core/ui-components/>,
<https://developer.adobe.com/commerce/php/development/security/cross-site-scripting/>.
