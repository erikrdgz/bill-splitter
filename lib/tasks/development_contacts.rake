namespace :dev do
  desc "Add local sample contacts to an existing contact's browser (CONTACT_ID=...)"
  task contacts: :environment do
    abort "Sample contacts are development-only." unless Rails.env.development?
    contact = Person.find(ENV.fetch("CONTACT_ID"))
    DevelopmentContacts.populate(contact.owner_token)
    puts "Local preview now has #{Person.owned_by(contact.owner_token).count} contacts."
  end
end

namespace :dev do
  namespace :contacts do
    desc "Enable sample contacts for empty browser sessions on this local server"
    task enable: :environment do
      abort "Sample contacts are development-only." unless Rails.env.development?
      DevelopmentContacts.flag_path.write("enabled\n")
      puts "Local contact preview enabled. Reload an empty browser session to load its sample contacts."
    end

    desc "Stop adding sample contacts to new local browser sessions"
    task disable: :environment do
      abort "Sample contacts are development-only." unless Rails.env.development?
      DevelopmentContacts.flag_path.delete if DevelopmentContacts.flag_path.exist?
      puts "Local contact preview disabled. Existing contacts are unchanged."
    end
  end
end
