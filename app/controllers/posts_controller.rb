# frozen_string_literal: true

class PostsController < ApplicationController
  prepend_before_action :authenticate_account!
  include PaymentRequired
  before_action :set_account_from_path
  before_action :set_post, only: %i[destroy edit update]

  layout 'dashboard_container'

  def index
    @posts = @account.posts

    @share_post = @account.posts.friendly.find(params[:share_post]) if params[:share_post]
  end

  def edit
    redirect_to page_posts_path(@account), notice: 'Post archived' if @post.archived?
    redirect_to page_post_draft_index_path(@account, @post) if @post.draft?
  end

  def create
    @post = @account.posts.build
    @post.save!(:validate => false)
    redirect_to page_post_draft_index_path(@account, @post)
  end

  def update
    @post.assign_attributes(post_params)
    @post.slug = nil # Resets FriendlyID

    respond_to do |format|
      if @post.update(post_params)
        format.html { redirect_to page_posts_path(@account), notice: 'Post updated' }
        format.turbo_stream unless params[:redirect]
      else
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy # rubocop:disable Metrics/MethodLength
    if @post.draft?
      @post.destroy!
      respond_to do |format|
        format.html { redirect_to page_posts_path(@account), notice: 'Draft destroyed', status: :see_other }
      end
    else
      @post.archive!
      respond_to do |format|
        format.html { redirect_to page_posts_path(@account), notice: 'Post deleted', status: :see_other }
        format.turbo_stream
      end
    end
  end

  private

  def post_params
    params.require(:post).permit(:subject, :body, :visibility, :published_at, :archived)
  end

  def set_post
    @post = @account.posts.friendly.find(params[:slug])
  end
end
