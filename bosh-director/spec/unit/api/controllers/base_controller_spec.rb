require 'spec_helper'
require 'rack/test'

module Bosh
  module Director
    module Api
      module Controllers
        class TestIdentityProvider
          attr_reader :request_env

          def initialize(authenticates)
            @authenticates = authenticates
          end

          def corroborate_user(request_env)
            @request_env = request_env
            raise AuthenticationError unless @authenticates
            "luke"
          end
        end

        describe BaseController do
          include Rack::Test::Methods

          let(:config) { Config.new(test_config) }
          subject(:app) { Support::TestController.new(config, requires_authentication) }

          let(:requires_authentication) { nil }
          let(:authenticates_successfully) { false }
          let(:identity_provider) { TestIdentityProvider.new(authenticates_successfully) }

          let(:temp_dir) { Dir.mktmpdir }
          let(:test_config) { base_config }
          let(:base_config) {
            blobstore_dir = File.join(temp_dir, 'blobstore')
            FileUtils.mkdir_p(blobstore_dir)

            config = Psych.load(spec_asset('test-director-config.yml'))
            config['dir'] = temp_dir
            config['blobstore'] = {
              'provider' => 'local',
              'options' => {'blobstore_path' => blobstore_dir}
            }
            config['snapshots']['enabled'] = true
            config
          }
          before { allow(config).to receive(:identity_provider).and_return(identity_provider) }
          after { FileUtils.rm_rf(temp_dir) }

          it 'sets the date header' do
            get '/test_route'
            expect(last_response.headers['Date']).not_to be_nil
          end

          it 'requires authentication' do
            get '/test_route'
            expect(last_response.status).to eq(401)
          end

          it 'requires authentication even for invalid routes' do
            get '/invalid_route'
            expect(last_response.status).to eq(401)
          end

          context 'when authorizaion is provided' do
            before { header('Authorization', 'Value') }

            it 'passes the request env to the identity provider' do
              header('X-Test-Header', 'Value')
              get '/test_route'
              expect(identity_provider.request_env['HTTP_X_TEST_HEADER']).to eq('Value')
            end

            context 'when authenticating successfully' do
              let(:authenticates_successfully) { true }

              it 'succeeds' do
                get '/test_route'
                expect(last_response.status).to eq(200)
                expect(last_response.body).to eq('Success with: luke')
              end
            end
          end

          context 'when failing to authenticate successfully' do
            let(:authenticates_successfully) { false }

            it 'rejects the request' do
              get '/test_route'
              expect(last_response.status).to eq(401)
            end
          end

          context 'when the controller does not require authentication' do
            let(:requires_authentication) { false }

            context 'when user provided credentials' do
              before { header('Authorization', 'Value') }

              context 'when credentials are invalid' do
                let(:authenticates_successfully) { false }

                it 'returns controller response' do
                  get '/test_route'
                  expect(last_response.status).to eq(200)
                  expect(last_response.body).to eq('Success with: No user')
                end
              end

              context 'when credentials are valid' do
                let(:authenticates_successfully) { true }

                it 'returns controller response' do
                  get '/test_route'
                  expect(last_response.status).to eq(200)
                  expect(last_response.body).to eq('Success with: luke')
                end
              end
            end

            context 'when user did not provide credentials' do
              it 'skips authorization' do
                get '/test_route'
                expect(last_response.status).to eq(200)
                expect(last_response.body).to eq('Success with: No user')
              end

              it 'skips authorization for invalid routes' do
                get '/invalid_route'
                expect(last_response.status).to eq(404)
              end
            end
          end
        end
      end
    end
  end
end
