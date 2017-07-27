# config valid only for current version of Capistrano
lock '3.8.2'

set :application, 'bestmade'
set :repo_url, 'git@github.com:tarungarg/manpreetdemo.git'

# Default branch is :master
# ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp

# Default deploy_to directory is /var/www/my_app_name
set :deploy_to, '/home/ubuntu/bestmade'

set :use_sudo, false
set :ssh_options, forward_agent: true
# Default value for :scm is :git
# set :scm, :git

# Default value for :format is :airbrussh.
# set :format, :airbrussh

# You can configure the Airbrussh format using :format_options.
# These are the defaults.
# set :format_options, command_output: true, log_file: 'log/capistrano.log', color: :auto, truncate: :auto

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
# set :linked_files, fetch(:linked_files, []).push('config/database.yml', 'config/secrets.yml')

# Default value for linked_dirs is []
# set :linked_dirs, fetch(:linked_dirs, []).push('log', 'tmp/pids', 'tmp/cache', 'tmp/sockets', 'public/system', 'public/assets')

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for keep_releases is 5
# set :keep_releases, 5
# Defaults to the primary :db server

set :migration_servers, -> { primary(fetch(:migration_role)) }

# Defaults to false
# Skip migration if files in db/migrate were not modified
set :conditionally_migrate, true


set :puma_threads, [0, 16]
set :puma_workers, 4
set :puma_init_active_record, true
set :puma_preload_app, true
set :puma_daemonize, true



set :puma_bind,       "unix://#{shared_path}/tmp/sockets/#{fetch(:application)}-puma.sock"
set :puma_state,      "#{shared_path}/tmp/pids/puma.state"
set :puma_pid,        "#{shared_path}/tmp/pids/puma.pid"
set :puma_access_log, "#{release_path}/log/puma.error.log"
set :puma_error_log,  "#{release_path}/log/puma.access.log"
set :puma_preload_app, true
set :puma_worker_timeout, nil
set :puma_init_active_record, true  # Change to false when not using ActiveRecord


# set the locations that we will look for changed assets to determine whether to precompile
# set :assets_dependencies, %w(app/assets lib/assets vendor/assets Gemfile config/routes.rb)

set :rbenv_type, :user # or :system, depends on your rbenv setup
set :rbenv_ruby, '2.1.10'
set :rbenv_prefix, "RBENV_ROOT=#{fetch(:rbenv_path)} RBENV_VERSION=#{fetch(:rbenv_ruby)} #{fetch(:rbenv_path)}/bin/rbenv exec"

set :assets_dependencies, %w(app/assets lib/assets vendor/assets Gemfile config/routes.rb)


before 'deploy:check', 'deploy:install_bundler'


# clear the previous precompile task
Rake::Task["deploy:assets:precompile"].clear_actions
class PrecompileRequired < StandardError; end



namespace :puma do
  desc 'Create Directories for Puma Pids and Socket'
  task :make_dirs do
    on roles(:app) do
      execute "mkdir #{shared_path}/tmp/sockets -p"
      execute "mkdir #{shared_path}/tmp/pids -p"
    end
  end

  before :start, :make_dirs
end


namespace :deploy do

  desc 'Initial Deploy'
  task :initial do
    on roles(:app) do
      before 'deploy:restart', 'puma:start'
      invoke 'deploy'
    end
  end

   desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      invoke 'puma:restart'
    end
  end

  after  :finishing,    :restart
  
  task :fix_absent_manifest_bug do
    on roles(:web) do
      # within release_path do  execute :mkdir,
      #   release_path.join('public', fetch(:assets_prefix))
      # end

      within release_path do  execute :touch,
        release_path.join('public', fetch(:assets_prefix), 'manifest-fix.temp')
      end
    end
  end

  before :updated, 'deploy:fix_absent_manifest_bug'

  desc 'Install bundler for the whole server'
  task :install_bundler  do
    on roles(:app) do
      execute "#{fetch(:rbenv_prefix)} gem install bundler"
    end
  end

  desc 'Install puma for the whole server'
  task :install_puma  do
    on roles(:app) do
      execute "#{fetch(:rbenv_prefix)}"
    end
  end

  desc 'Install puma for the whole server'
  task :install_puma  do
    on roles(:app) do
      execute "#{fetch(:rbenv_prefix)}"
    end
  end

  namespace :assets do
    desc 'Build assets tar'
    task :build_assets_tar do
      temp_assets_file = 'tmp/assets.tar.gz'
      assets_folder = 'public/assets'
      back_folder = '../..'

      run_locally do
        execute 'npm run build' rescue nil

        execute "rm #{temp_assets_file}" rescue nil
        execute "rm -rf #{assets_folder}/*"

        with rails_env: fetch(:rails_env) do
          execute 'rake assets:precompile'
        end
        ['filosofia', 'icon-fonts', 'fontawesome-webfont', 'Interstate'].each do |font|
          execute "rsync -avz app/assets/fonts/#{font}/*.woff #{assets_folder}/#{font}/"
          execute "rsync -avz app/assets/fonts/#{font}/*.ttf #{assets_folder}/#{font}/"
        end

        ['fontawesome-webfont'].each do |font|
          execute "rsync -avz app/assets/fonts/#{font}/*.woff2 #{assets_folder}/"
          execute "rsync -avz app/assets/fonts/#{font}/*.woff #{assets_folder}/"
          execute "rsync -avz app/assets/fonts/#{font}/*.ttf #{assets_folder}/"
        end

        ['search-nav-icon-light.svg', 'cart-nav-icon.svg', 'cart-nav-icon-light.svg', 'cart-nav-icon-new.svg', 'right-arrow.png', 'left-arrow.png'].each do |file|
          execute "rsync -avz app/assets/images/#{file} #{assets_folder}/"
        end

        execute "cd #{assets_folder} && tar zcvf #{back_folder}/#{temp_assets_file} *"
        execute "rm -rf #{assets_folder}/*"
      end
    end

    desc 'Delete assets tar'
    task :delete_assets_tar do
      temp_assets_file = 'tmp/assets.tar.gz'

      run_locally do
        execute "rm #{temp_assets_file}" rescue nil
      end
    end

    desc 'Run the precompile task locally and upload to server'
    task :upload do
      on roles(:app) do
        temp_assets_file = 'tmp/assets.tar.gz'
        assets_folder = 'public/assets'
        back_folder = '../..'

        # Upload precompiled assets
        execute "rm -rf #{shared_path}/#{assets_folder}/*"
        upload! "tmp/assets.tar.gz", "#{shared_path}/#{assets_folder}/assets.tar.gz"
        execute "cd #{shared_path}/#{assets_folder} && tar zxvf assets.tar.gz && rm assets.tar.gz"
      end
    end

    desc "Precompile assets if changed"
    task :precompile do
      on roles(:app) do

      end
    end
  end
end