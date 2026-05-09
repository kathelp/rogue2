require "rails_helper"

RSpec.describe AccountabilityMailer, type: :mailer do
  describe "#weekly_digest" do
    let(:tenant) do
      create(
        :tenant,
        :active,
        dealership_name: "Smith Toyota",
        gm_name: "Jane Smith",
        gm_email: "jane@smithtoyota.com",
        onboarding_token: "digesttoken9999"
      )
    end

    context("with at least one configured Responsibility") do
      let(:question) do
        create(
          :tenant_question,
          tenant: tenant,
          key: "marketing_strategy",
          prompt: "Who controls your marketing strategy?",
          default_cadence: "monthly",
          status: "answered"
        )
      end

      let(:contact) do
        create(
          :contact,
          tenant: tenant,
          email: "alex@smithtoyota.com",
          classification: "internal_staff"
        )
      end

      let!(:responsibility) do
        create(
          :responsibility,
          tenant: tenant,
          tenant_question: question,
          primary_contact: contact
        )
      end

      let!(:source) do
        create(
          :source,
          :configured,
          tenant: tenant,
          domain: "marketing",
          responsibility_key: "marketing_strategy",
          configured_by_contact: contact
        )
      end

      let(:mail) { described_class.with(tenant: tenant).weekly_digest }

      it "sends to the GM email" do
        expect(mail.to).to(eq(["jane@smithtoyota.com"]))
      end

      it "has the canonical subject containing the dealership name" do
        expect(mail.subject).to(eq("Smith Toyota — weekly accountability digest"))
      end

      it "has both HTML and plain-text parts" do
        expect(mail.html_part).not_to(be_nil)
        expect(mail.text_part).not_to(be_nil)
      end

      it "lists the responsibility row in the HTML body" do
        body = mail.html_part.body.decoded
        expect(body).to(include("marketing strategy"))
        expect(body).to(include("alex@smithtoyota.com"))
      end

      it "lists the responsibility row in the text body" do
        body = mail.text_part.body.decoded
        expect(body).to(include("marketing strategy"))
        expect(body).to(include("alex@smithtoyota.com"))
      end

      it "includes a single 'Open dashboard' CTA linking to /dashboard/<signed_id>" do
        body = mail.html_part.body.decoded
        expect(body).to(include("Open dashboard"))
        expect(body).to(match(%r{/dashboard/[A-Za-z0-9._\-]+}))
      end

      it "the dashboard CTA URL also appears in the text body" do
        expect(mail.text_part.body.decoded).to(match(%r{/dashboard/[A-Za-z0-9._\-]+}))
      end

      # FEAT-005 — badge color
      it "renders the per-row status as an inline-colored badge span" do
        body = mail.html_part.body.decoded
        expect(body).to(match(/<span[^>]*background:\s*#[0-9a-f]+[^>]*>(Pending first submission|Awaiting setup)/i))
      end
    end

    context("with no configured responsibilities (empty state)") do
      let(:mail) { described_class.with(tenant: tenant).weekly_digest }

      it "still ships with an explicit empty-state message" do
        body = mail.html_part.body.decoded
        expect(body).to(match(/no submissions/i))
      end

      it "subject is unchanged in empty state" do
        expect(mail.subject).to(eq("Smith Toyota — weekly accountability digest"))
      end
    end
  end
end
