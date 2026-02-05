# frozen_string_literal: true

class DraftController < ApplicationController
  prepend_before_action :authenticate_account!
  before_action :set_account_from_path, :set_post
  layout 'dashboard'

  include Wicked::Wizard

  steps :write, :review, :confirmation

  def show
    return redirect_to page_post_draft_path(@account, @post, step) if params[:post_slug] != @post.slug

    case step
    when :write, :review
      @email_address = EmailAddress.new
      return redirect_to page_post_path(@account, @post) if @post.published?
    when :confirmation
      return redirect_to page_post_draft_path(@account, @post, :write) unless @post.published?
    end

    render_wizard
  end

  def update # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    options = {}

    case step
    when :write
      @post.assign_attributes(post_params)
      @post.slug = nil # Resets FriendlyID
      @post.save!(:validate => false)

      unless params[:commit] == 'review'
        respond_to do |format|
          format.html { redirect_to page_posts_path, notice: 'Draft saved' }
          format.turbo_stream unless params[:commit] == 'save'
        end
        return
      end

      options[:status] = :bad_request unless @post.valid?
    when :review
      @post.published_at = Time.zone.now
      @post.snapshot_images! # Wabi-sabi mode: capture current photo/cover for historical display
      @post.save!
      @post.send_newsletter
      @post.account.update(pinned_post: @post)
      return redirect_to page_posts_path(@account, share_post: @post.slug), status: :see_other, notice: 'Post published'
    end

    render_wizard @post, options
  end

  private

  def post_params
    params.require(:post).permit(:subject, :body)
  end

  def set_post
    @post = @account.posts.friendly.find(params[:post_slug])

    redirect_to page_post_draft_path(@account, @post, :draft) unless @post.draft?
  end
end
