import * as ActiveStorage from "@rails/activestorage";
import "trix";
import "@rails/actiontext";

ActiveStorage.start();

// Init
const Trix = window.Trix;
Trix.config.toolbar.getDefaultHTML = toolbarDefaultHTML;
document.addEventListener(
  "trix-initialize",
  (event) => {
    const toolbars = document.querySelectorAll("trix-toolbar");
    const html = Trix.config.toolbar.getDefaultHTML();
    toolbars.forEach((toolbar) => (toolbar.innerHTML = html));
  },
  {
    once: true,
  },
);

// Headings
Trix.config.blockAttributes.heading1.tagName = "h2";
Trix.config.blockAttributes.heading2 = {
  tagName: "h3",
  terminal: true,
  breakOnReturn: true,
  group: false,
};

// Captions
Trix.config.attachments.preview.caption.name = false;
Trix.config.attachments.preview.caption.size = false;
Trix.config.attachments.file.caption.size = false;
Trix.config.lang.captionPlaceholder = "Add a caption (optional)";

document.addEventListener("trix-change", function (event) {
  const editor = event.target.editor;
  const position = editor.getPosition();

  if (
    position < 2 ||
    editor.attributeIsActive("code") ||
    editor.attributeIsActive("heading1") ||
    editor.attributeIsActive("heading2") ||
    editor.attributeIsActive("quote") // assuming 'quote' is the blockquote attribute in Trix, adjust if different
  ) {
    return;
  }

  let text = editor.getDocument().toString().substring(position - 5, position);

  const blockquote = /\n> /;

  const heading1 = /\n# /;
  const heading2 = /\n## /;
  const codeBlock = /\n```\n/;

  const bullet = /\n[*-] /;
  const number = /\n1\. /;

  let type,
    offset = null;

  if (position < 5) {
    text = "\n" + text;
  }

  if (bullet.test(text)) {
    offset = 2;
    type = "bullet";
  } else if (number.test(text)) {
    offset = 3;
    type = "number";
  } else if (heading1.test(text)) {
    offset = 2;
    type = "heading1";
  } else if (heading2.test(text)) {
    offset = 3;
    type = "heading2";
  } else if (codeBlock.test(text)) {
    offset = 4;
    type = "code";
  } else if (blockquote.test(text)) {
    offset = 2;
    type = "quote";
  }

  if (type) {
    editor.recordUndoEntry("autolist");
    editor.setSelectedRange([position - offset, position]);
    editor.deleteInDirection("forward");
    editor.activateAttribute(type);
  }
});

function toolbarDefaultHTML() {
  const { lang } = Trix.config;
  return `
    <div class="flex flex-row justify-between bg-white h-auto items-center py-1">
      <span class="space-x-1 flex items-center" data-trix-button-group="text-tools">
        <button type="button" class="btn btn-secondary btn-small" data-trix-attribute="bold" data-trix-key="b" title="${lang.bold}" tabindex="-1">
          <span class="h-5 w-5 font-bold">B</span>
        </button>
        <button type="button" class="btn btn-secondary btn-small" data-trix-attribute="italic" data-trix-key="i" title="${lang.italic}" tabindex="-1">
          <span class="h-5 w-5 font-semibold italic">I</span>
        </button>
        <button type="button" class="btn btn-secondary btn-small" data-trix-attribute="heading1" title="${lang.heading1}" tabindex="-1">
          <span class="h-5 w-5 font-semibold">H1</span>
        </button>
        <button type="button" class="btn btn-secondary btn-small" data-trix-attribute="heading2" title="Subheading" tabindex="-1">
          <span class="h-5 w-5 font-medium">H2</span>
        </button>
        <button type="button" class="btn btn-secondary btn-small" data-trix-attribute="quote" title="${lang.quote}" tabindex="-1">
          <svg xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="0 0 16 16" class="w-5 h-5">
            <path d="M12 12a1 1 0 0 0 1-1V8.558a1 1 0 0 0-1-1h-1.388c0-.351.021-.703.062-1.054.062-.372.166-.703.31-.992.145-.29.331-.517.559-.683.227-.186.516-.279.868-.279V3c-.579 0-1.085.124-1.52.372a3.322 3.322 0 0 0-1.085.992 4.92 4.92 0 0 0-.62 1.458A7.712 7.712 0 0 0 9 7.558V11a1 1 0 0 0 1 1h2Zm-6 0a1 1 0 0 0 1-1V8.558a1 1 0 0 0-1-1H4.612c0-.351.021-.703.062-1.054.062-.372.166-.703.31-.992.145-.29.331-.517.559-.683.227-.186.516-.279.868-.279V3c-.579 0-1.085.124-1.52.372a3.322 3.322 0 0 0-1.085.992 4.92 4.92 0 0 0-.62 1.458A7.712 7.712 0 0 0 3 7.558V11a1 1 0 0 0 1 1h2Z"/>
          </svg>
        </button>
        <button type="button" class="btn btn-secondary btn-small" data-trix-attribute="code" title="${lang.code}" tabindex="-1">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5">
            <path fill-rule="evenodd" d="M6.28 5.22a.75.75 0 010 1.06L2.56 10l3.72 3.72a.75.75 0 01-1.06 1.06L.97 10.53a.75.75 0 010-1.06l4.25-4.25a.75.75 0 011.06 0zm7.44 0a.75.75 0 011.06 0l4.25 4.25a.75.75 0 010 1.06l-4.25 4.25a.75.75 0 01-1.06-1.06L17.44 10l-3.72-3.72a.75.75 0 010-1.06zM11.377 2.011a.75.75 0 01.612.867l-2.5 14.5a.75.75 0 01-1.478-.255l2.5-14.5a.75.75 0 01.866-.612z" clip-rule="evenodd" />
          </svg>
        </button>
        <button type="button" class="btn btn-secondary btn-small" data-trix-attribute="bullet" title="${lang.bullets}" tabindex="-1">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5">
            <path fill-rule="evenodd" d="M6 4.75A.75.75 0 016.75 4h10.5a.75.75 0 010 1.5H6.75A.75.75 0 016 4.75zM6 10a.75.75 0 01.75-.75h10.5a.75.75 0 010 1.5H6.75A.75.75 0 016 10zm0 5.25a.75.75 0 01.75-.75h10.5a.75.75 0 010 1.5H6.75a.75.75 0 01-.75-.75zM1.99 4.75a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1v-.01zM1.99 15.25a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1v-.01zM1.99 10a1 1 0 011-1H3a1 1 0 011 1v.01a1 1 0 01-1 1h-.01a1 1 0 01-1-1V10z" clip-rule="evenodd" />
          </svg>
        </button>
        <button type="button" class="btn btn-secondary btn-small" data-trix-attribute="href" data-trix-action="link" data-trix-key="k" title="${lang.link}" tabindex="-1">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5">
            <path d="M12.232 4.232a2.5 2.5 0 013.536 3.536l-1.225 1.224a.75.75 0 001.061 1.06l1.224-1.224a4 4 0 00-5.656-5.656l-3 3a4 4 0 00.225 5.865.75.75 0 00.977-1.138 2.5 2.5 0 01-.142-3.667l3-3z" />
            <path d="M11.603 7.963a.75.75 0 00-.977 1.138 2.5 2.5 0 01.142 3.667l-3 3a2.5 2.5 0 01-3.536-3.536l1.225-1.224a.75.75 0 00-1.061-1.06l-1.224 1.224a4 4 0 105.656 5.656l3-3a4 4 0 00-.225-5.865z" />
          </svg>
        </button>
        <button type="button" class="btn btn-secondary btn-small" data-trix-action="attachFiles" title="${lang.attachFiles}" tabindex="-1">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5">
            <path fill-rule="evenodd" d="M1 5.25A2.25 2.25 0 013.25 3h13.5A2.25 2.25 0 0119 5.25v9.5A2.25 2.25 0 0116.75 17H3.25A2.25 2.25 0 011 14.75v-9.5zm1.5 5.81v3.69c0 .414.336.75.75.75h13.5a.75.75 0 00.75-.75v-2.69l-2.22-2.219a.75.75 0 00-1.06 0l-1.91 1.909.47.47a.75.75 0 11-1.06 1.06L6.53 8.091a.75.75 0 00-1.06 0l-2.97 2.97zM12 7a1 1 0 11-2 0 1 1 0 012 0z" clip-rule="evenodd" />
          </svg>
        </button>
      </span>
    </div>
    <div class="trix-dialogs" data-trix-dialogs>
      <div class="trix-dialog trix-dialog--link" data-trix-dialog="href" data-trix-dialog-attribute="href">
        <div class="flex space-x-1 trix-dialog__link-fields">
          <input type="url" name="href" class="form-input trix-input trix-input--dialog" placeholder="${lang.urlPlaceholder}" aria-label="${lang.url}" required data-trix-input disabled="disabled">
          <div class="space-x-1 flex items-stretch">
            <input type="button" class="btn btn-primary" value="${lang.link}" data-trix-method="setAttribute">
            <input type="button" class="btn btn-secondary" value="${lang.unlink}" data-trix-method="removeAttribute">
          </div>
        </div>
      </div>
    </div>
  </div>
  `;
}
