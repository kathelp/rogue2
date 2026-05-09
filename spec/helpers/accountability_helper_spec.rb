require "rails_helper"

RSpec.describe AccountabilityHelper, type: :helper do
  describe "#status_badge" do
    it "renders an inline-styled span for :on_time (green)" do
      html = helper.status_badge(:on_time)
      expect(html).to(match(/<span/))
      expect(html).to(match(/On time/))
      expect(html).to(match(/background:\s*#[0-9a-f]+/i))
    end

    it "renders gray for :pending_setup" do
      html = helper.status_badge(:pending_setup)
      expect(html).to(match(/Awaiting setup/))
    end

    it "renders gray for :pending_first_submission" do
      html = helper.status_badge(:pending_first_submission)
      expect(html).to(match(/Pending first submission/))
    end

    it "renders amber for :late" do
      html = helper.status_badge(:late)
      expect(html).to(match(/Late/))
    end

    it "renders red for :overdue" do
      html = helper.status_badge(:overdue)
      expect(html).to(match(/Overdue/))
    end

    it "renders the symbol value for unknown statuses (graceful fallback)" do
      html = helper.status_badge(:something_new)
      expect(html).to(match(/something_new|Something new/i))
    end
  end
end
