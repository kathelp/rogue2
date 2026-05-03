namespace :rogue do
  namespace :tenants do
    desc "Seed a Tenant. Usage: bin/rails 'rogue:tenants:seed[Smith Toyota,Jane Smith,jane@smithtoyota.com]'"
    task :seed, %i[dealership_name gm_name gm_email] => :environment do |_t, args|
      result = Tenant::Seeder.call(
        dealership_name: args[:dealership_name],
        gm_name: args[:gm_name],
        gm_email: args[:gm_email]
      )
      if result.success?
        puts "Seeded #{result.tenant.dealership_name} (id=#{result.tenant.id})"
        puts "   confirmation queued for #{result.tenant.gm_email}"
      else
        puts "Failed: #{result.errors.join(', ')}"
        exit 1
      end
    end
  end
end
