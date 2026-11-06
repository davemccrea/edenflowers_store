defmodule EdenflowersWeb.VoucherSkeleton do
  @moduledoc """
  The gift voucher's outline, shown while its preview renders: on the voucher
  checkout and on the order page after buying one. Place it in a box with the
  voucher's 210/148 shape; it fills that box.
  """
  use EdenflowersWeb, :html

  def voucher_skeleton(assigns) do
    ~H"""
    <div
      class="bg-cream grid-cols-[136fr_74fr] absolute inset-0 grid"
      aria-hidden="true"
      data-testid="voucher-preview-skeleton"
    >
      <div class="px-[9%] flex flex-col justify-center gap-3 motion-safe:animate-pulse">
        <div class="bg-cream-content/10 h-2 w-2/3"></div>
        <div class="bg-cream-content/10 h-1.5 w-4/5"></div>
        <div class="bg-cream-content/10 h-1.5 w-1/2"></div>
      </div>
      <div class="bg-primary flex items-center justify-center">
        <div class="bg-cream/20 h-3 w-1/2 motion-safe:animate-pulse"></div>
      </div>
    </div>
    """
  end
end
