module Bosh::Director
  module Jobs
    class UpdateDeployment < BaseJob
      include LockHelper

      @queue = :normal

      def self.job_type
        :update_deployment
      end

      def initialize(manifest_file_path, cloud_config_id, options = {})
        @blobstore = App.instance.blobstores.blobstore
        @manifest_file_path = manifest_file_path
        @options = options
        @cloud_config_id = cloud_config_id
      end

      def perform
        with_deployment_lock(deployment_plan) do
          logger.info('Updating deployment')
          notifier.send_start_event
          prepare_step.perform
          compile_step.perform
          update_step.perform
          notifier.send_end_event
          logger.info('Finished updating deployment')

          "/deployments/#{deployment_plan.name}"
        end
      rescue Exception => e
        notifier.send_error_event e
        raise e
      ensure
        FileUtils.rm_rf(@manifest_file_path)
      end

      private

      # Job tasks

      def prepare_step
        DeploymentPlan::Steps::PrepareStep.new(self, assembler)
      end

      def compile_step
        DeploymentPlan::Steps::PackageCompileStep.new(deployment_plan)
      end

      def update_step
        resource_pool_updaters = deployment_plan.resource_pools.map do |resource_pool|
          ResourcePoolUpdater.new(resource_pool)
        end
        resource_pools = DeploymentPlan::ResourcePools.new(event_log, resource_pool_updaters)
        DeploymentPlan::Steps::UpdateStep.new(self, event_log, resource_pools, assembler, deployment_plan, multi_job_updater)
      end

      # Job dependencies

      def assembler
        @assembler ||= DeploymentPlan::Assembler.new(deployment_plan)
      end

      def notifier
        @notifier ||= DeploymentPlan::Notifier.new(deployment_plan, Config.nats_rpc, logger)
      end

      def deployment_plan
        @deployment_plan ||= begin
          logger.info('Reading deployment manifest')
          manifest_text = File.read(@manifest_file_path)
          logger.debug("Manifest:\n#{manifest_text}")
          deployment_manifest = Psych.load(manifest_text)

          plan_options = {
            'recreate' => !!@options['recreate'],
            'job_states' => @options['job_states'] || {},
            'job_rename' => @options['job_rename'] || {}
          }
          logger.info('Creating deployment plan')
          logger.info("Deployment plan options: #{plan_options.pretty_inspect}")

          cloud_config = Bosh::Director::Models::CloudConfig[@cloud_config_id]

          plan = DeploymentPlan::Planner.parse(deployment_manifest, cloud_config, plan_options, event_log, logger)
          logger.info('Created deployment plan')
          plan
        end
      end

      def multi_job_updater
        @multi_job_updater ||= begin
          DeploymentPlan::BatchMultiJobUpdater.new(JobUpdaterFactory.new(@blobstore))
        end
      end
    end
  end
end
