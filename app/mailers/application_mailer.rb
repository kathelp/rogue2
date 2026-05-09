class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"
  helper :dev_tooling
end
