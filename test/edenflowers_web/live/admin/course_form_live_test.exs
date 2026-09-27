defmodule EdenflowersWeb.Admin.CourseFormLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Courses.Course

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    %{conn: conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)}
  end

  test "creates a course with a Swedish translation", %{conn: conn} do
    tax_rate = generate(tax_rate())

    {:ok, view, _html} = live(conn, ~p"/admin/courses/new")

    photo = file_input(view, "#course-form", "photo_form[image_slug]", [photo("Kransar ä.jpg")])
    render_upload(photo, "Kransar ä.jpg")

    assert {:error, {:live_redirect, %{to: "/admin/courses"}}} =
             view
             |> form("#course-form",
               form: %{
                 name: "Autumn wreaths",
                 description: "Make a wreath.",
                 date: "2030-10-10",
                 start_time: "10:00",
                 end_time: "13:00",
                 register_before: "2030-10-01",
                 total_places: "8",
                 price: "85.00",
                 tax_rate_id: tax_rate.id,
                 location_name: "Minimossen",
                 location_address: "Myrvägen 1",
                 translations: %{"sv-FI": %{name: "Höstkransar"}}
               }
             )
             |> render_submit()

    [course] = Ash.read!(Course, authorize?: false)
    assert course.name == "Autumn wreaths"
    assert course.translations."sv-FI".name == "Höstkransar"
    assert "local:///uploads/" <> filename = course.image_slug
    assert filename =~ ~r/^kransar-a-[0-9a-f]{6}\.jpg$/
    assert File.read!(Path.join(Application.fetch_env!(:edenflowers, :uploads_dir), filename)) == "jpeg bytes"
  end

  test "edits an existing course", %{conn: conn} do
    course = generate(course(total_places: 8))

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

    view |> form("#course-form", form: %{total_places: "12"}) |> render_submit()

    assert Ash.get!(Course, course.id, authorize?: false).total_places == 12
  end

  defp photo(name), do: %{name: name, content: "jpeg bytes", type: "image/jpeg"}
end
