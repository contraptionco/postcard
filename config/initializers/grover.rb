# frozen_string_literal: true

Grover.configure do |config|
  config.options = {
    viewport: {
      width: 1128,
      height: 600
    },
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-accelerated-2d-canvas',
      '--no-first-run',
      '--no-zygote',
      '--single-process',
      '--disable-gpu'
    ]
  }
end
