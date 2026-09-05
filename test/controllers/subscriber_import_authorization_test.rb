# frozen_string_literal: true

require 'test_helper'

class SubscriberImportAuthorizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:grandfathered_user)
    @other_account = accounts(:new_user)
    @imports = []
    @uploads = []
    host! Rails.configuration.base_host
    clear_enqueued_jobs
  end

  teardown do
    @imports.each { |import| import.file.purge if import.file.attached? }
    @uploads.each(&:close!)
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test 'guests cannot upload or approve subscriber imports' do
    import = existing_import(@account)
    assert_no_difference('SubscribersImport.count') do
      post page_subscribers_imports_path(@account), params: { subscribers_import: upload_params }
    end
    assert_response :redirect
    assert_equal new_account_session_path, URI(response.location).path

    patch page_subscribers_import_path(@account, import), params: { approved: 'true' }
    assert_response :redirect
    assert_equal new_account_session_path, URI(response.location).path
    assert_not import.reload.approved?
  end

  test 'authors cannot list, create, or approve imports on another account' do
    import = existing_import(@other_account)
    sign_in @account

    get page_subscribers_imports_path(@other_account)
    assert_redirected_to page_path(@account)
    assert_no_difference('SubscribersImport.count') do
      post page_subscribers_imports_path(@other_account), params: { subscribers_import: upload_params }
    end
    assert_redirected_to page_path(@account)

    patch page_subscribers_import_path(@other_account, import), params: { approved: 'true' }
    assert_redirected_to page_path(@account)
    assert_not import.reload.approved?
  end

  test 'upload binds the import to the authenticated account and ignores forged approval and ownership' do
    sign_in @account
    assert_difference('SubscribersImport.count', 1) do
      post page_subscribers_imports_path(@account), params: {
        approved: 'true', subscribers_import: upload_params.merge(account_id: @other_account.id, approved: true)
      }
    end
    import = SubscribersImport.order(:id).last
    @imports << import

    assert_redirected_to page_subscribers_imports_path(@account)
    assert_equal @account.id, import.account_id
    assert_equal Rails.configuration.solo_mode, import.approved?
    assert_equal ['uploaded-reader@example.com'], import.emails
  end

  test 'owners receive forbidden when attempting to approve their own import' do
    import = existing_import(@account)
    sign_in @account
    clear_enqueued_jobs

    assert_no_enqueued_jobs do
      patch page_subscribers_import_path(@account, import), params: { approved: 'true' }
    end
    assert_response :forbidden
    assert_not import.reload.approved?
  end

  test 'admin can approve another author’s import but cannot move it or approve an id under the wrong account' do
    import = existing_import(@other_account)
    @account.update!(admin: true)
    sign_in @account
    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: SubscribersImportJob do
      patch page_subscribers_import_path(@other_account, import), params: {
        approved: 'true', subscribers_import: { account_id: @account.id }
      }
    end
    assert_redirected_to page_subscribers_imports_path(@other_account)
    assert import.reload.approved?
    assert_equal @other_account.id, import.account_id

    assert_raises(ActiveRecord::RecordNotFound) do
      patch page_subscribers_import_path(@account, import), params: { approved: 'false' }
    end
    assert import.reload.approved?
  end

  test 'missing source explanation returns validation errors without storing an import or queuing work' do
    sign_in @account
    clear_enqueued_jobs

    assert_no_difference('SubscribersImport.count') do
      assert_no_enqueued_jobs do
        post page_subscribers_imports_path(@account), params: {
          subscribers_import: upload_params.merge(sources_description: '')
        }
      end
    end
    assert_response :unprocessable_entity
    assert_select 'form', count: 1
    assert_includes response.body, 'Sources description'
  end

  private

  def existing_import(account)
    import = account.subscribers_imports.new(sources_description: 'Existing opted-in readers')
    import.file.attach(io: StringIO.new("existing-reader@example.com\n"), filename: 'readers.csv', content_type: 'text/csv')
    import.save!
    import.update_column(:approved, false)
    @imports << import
    import
  end

  def upload_params
    file = Tempfile.new(['subscriber-import-test', '.csv'])
    file.write("Email\nUPLOADED-READER@example.com\n")
    file.rewind
    @uploads << file
    {
      file: Rack::Test::UploadedFile.new(file.path, 'text/csv'),
      sources_description: 'Readers explicitly opted in to the previous newsletter'
    }
  end
end
