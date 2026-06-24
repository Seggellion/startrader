namespace :tick do
  desc "Ensure tick jobs are scheduled if TickControl is running"
  task ensure: :environment do
    TickWatchdogJob.perform_now
  end

  desc "Print tick health"
  task health: :environment do
    TickControl.instance.health.each do |key, value|
      puts "#{key}: #{value}"
    end
  end

  desc "Start tick"
  task start: :environment do
    TickControl.instance.start!
    TickWatchdogJob.perform_now
    puts "Tick engine started."
  end

  desc "Stop tick"
  task stop: :environment do
    TickControl.instance.stop!
    puts "Tick engine stopped."
  end
end
