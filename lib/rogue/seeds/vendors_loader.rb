require "csv"

module Rogue
  module Seeds
    class VendorsLoader
      CSV_PATH = Rails.root.join("db/seeds/vendors/automotive_vendors.csv")

      def self.call
        new.call
      end

      def call
        loaded = 0
        skipped = 0

        CSV.foreach(CSV_PATH, headers: true) do |row|
          name = row["name"].to_s.strip
          next if name.blank?

          domains = split_pipe(row["domains"])
          aliases = split_pipe(row["aliases"])
          categories = split_pipe(row["categories"])

          vendor = Vendor.find_or_initialize_by(name: name)
          if vendor.new_record?
            vendor.assign_attributes(
              domains: domains,
              aliases: aliases,
              categories: categories,
              state: "active",
              source: "seed"
            )
            vendor.save!
            loaded += 1
          else
            skipped += 1
          end
        end

        Rails.logger.info(
          message: "VendorsLoader complete",
          loaded: loaded,
          skipped: skipped
        )
      end

      private

      def split_pipe(value)
        return [] if value.blank?

        value.split("|").map { |v| v.strip.downcase }.reject(&:blank?)
      end
    end
  end
end
