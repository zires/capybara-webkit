require 'spec_helper'
require 'capybara/webkit/driver'

describe Capybara::Webkit::Driver do
  include AppRunner

  context "malloc app" do
    let(:driver) do
      driver_for_html "<html><body>#{nest_tags}</body></html>"
    end

    it "generates a malloc error" do
      if ENV['MALLOC_DEBUG']
        100_000.times do
          driver.visit "/"
          driver.reset!
        end
      else
        pending 'Set MALLOC_DEBUG to debug malloc errors'
      end
    end

    def nest_tags(count = 1000)
      if count == 0
        'text'
      else
        "<p>#{nest_tags(count - 1)}</p>"
      end
    end
  end
end
