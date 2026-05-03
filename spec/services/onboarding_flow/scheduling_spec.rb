require "rails_helper"

RSpec.describe OnboardingFlow::Scheduling do
  let(:eastern) { "America/New_York" }
  let(:pacific) { "America/Los_Angeles" }

  def et(year, month, day, hour, min = 0)
    ActiveSupport::TimeZone["America/New_York"].local(year, month, day, hour, min, 0)
  end

  def pt(year, month, day, hour, min = 0)
    ActiveSupport::TimeZone["America/Los_Angeles"].local(year, month, day, hour, min, 0)
  end

  # -------------------------------------------------------------------------
  describe ".in_business_window?" do
    context "Mon-Fri within 9:30am-6pm" do
      it "returns true for Monday at 10am ET" do
        # 2026-05-04 is Monday
        expect(described_class.in_business_window?(et(2026, 5, 4, 10), time_zone: eastern)).to be true
      end

      it "returns true for Friday at 5:59pm ET" do
        # 2026-05-08 is Friday
        expect(described_class.in_business_window?(et(2026, 5, 8, 17, 59), time_zone: eastern)).to be true
      end

      it "returns true at exactly 9:30am" do
        expect(described_class.in_business_window?(et(2026, 5, 4, 9, 30), time_zone: eastern)).to be true
      end
    end

    context "outside business hours" do
      it "returns false before 9:30am on a weekday" do
        expect(described_class.in_business_window?(et(2026, 5, 4, 9, 15), time_zone: eastern)).to be false
      end

      it "returns false at exactly 6pm (end-exclusive)" do
        expect(described_class.in_business_window?(et(2026, 5, 4, 18, 0), time_zone: eastern)).to be false
      end

      it "returns false after 6pm on a weekday" do
        expect(described_class.in_business_window?(et(2026, 5, 4, 20, 0), time_zone: eastern)).to be false
      end

      it "returns false on Saturday" do
        # 2026-05-09 is Saturday
        expect(described_class.in_business_window?(et(2026, 5, 9, 10), time_zone: eastern)).to be false
      end

      it "returns false on Sunday" do
        # 2026-05-10 is Sunday
        expect(described_class.in_business_window?(et(2026, 5, 10, 10), time_zone: eastern)).to be false
      end
    end
  end

  # -------------------------------------------------------------------------
  describe ".next_business_window" do
    context "when input is already within the business window" do
      it "returns the input unchanged" do
        time = et(2026, 5, 4, 10, 0) # Monday 10am ET
        result = described_class.next_business_window(after: time, time_zone: eastern)
        expect(result).to eq(time)
      end
    end

    context "when input is after 6pm on a weekday" do
      it "returns next day at 9:30am" do
        # Tuesday evening → Wednesday morning
        tuesday_evening = et(2026, 5, 5, 20, 0) # Tuesday 8pm ET
        result = described_class.next_business_window(after: tuesday_evening, time_zone: eastern)
        expect(result.wday).to eq(3) # Wednesday
        expect(result.hour).to eq(9)
        expect(result.min).to eq(30)
        expect(result.time_zone.name).to eq("America/New_York")
      end
    end

    context "when input is before 9:30am on a weekday" do
      it "returns same day at 9:30am" do
        # Wednesday 7am → Wednesday 9:30am
        wednesday_early = et(2026, 5, 6, 7, 0)
        result = described_class.next_business_window(after: wednesday_early, time_zone: eastern)
        expect(result.wday).to eq(3) # Wednesday
        expect(result.hour).to eq(9)
        expect(result.min).to eq(30)
      end
    end

    context "when input is Saturday" do
      it "returns Monday 9:30am" do
        saturday = et(2026, 5, 9, 10, 0) # Saturday 10am ET
        result = described_class.next_business_window(after: saturday, time_zone: eastern)
        expect(result.wday).to eq(1) # Monday
        expect(result.hour).to eq(9)
        expect(result.min).to eq(30)
      end
    end

    context "when input is Sunday" do
      it "returns Monday 9:30am" do
        sunday = et(2026, 5, 10, 10, 0) # Sunday 10am ET
        result = described_class.next_business_window(after: sunday, time_zone: eastern)
        expect(result.wday).to eq(1) # Monday
        expect(result.hour).to eq(9)
        expect(result.min).to eq(30)
      end
    end

    context "Friday late evening → Monday morning" do
      it "skips the weekend and returns Monday 9:30am" do
        friday_evening = et(2026, 5, 8, 19, 0) # Friday 7pm ET
        result = described_class.next_business_window(after: friday_evening, time_zone: eastern)
        expect(result.wday).to eq(1) # Monday
        expect(result.hour).to eq(9)
        expect(result.min).to eq(30)
      end
    end

    context "with Pacific timezone" do
      it "uses the tenant's local timezone for the window calculation" do
        # 10am Pacific on a Monday is in window for a PT tenant
        pt_monday_10am = pt(2026, 5, 4, 10, 0)
        result = described_class.next_business_window(after: pt_monday_10am, time_zone: pacific)
        # Should return the same time (already in window)
        expect(result.in_time_zone(pacific).hour).to eq(10)
        expect(result.in_time_zone(pacific).wday).to eq(1) # Monday
      end

      it "bumps a Pacific Saturday to Monday 9:30am Pacific" do
        pt_saturday = pt(2026, 5, 9, 11, 0) # Saturday 11am Pacific
        result = described_class.next_business_window(after: pt_saturday, time_zone: pacific)
        expect(result.in_time_zone(pacific).wday).to eq(1) # Monday
        expect(result.in_time_zone(pacific).hour).to eq(9)
        expect(result.in_time_zone(pacific).min).to eq(30)
      end
    end
  end
end
