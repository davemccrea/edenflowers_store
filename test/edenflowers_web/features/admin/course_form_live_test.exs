defmodule EdenflowersWeb.Admin.CourseFormLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator
  import Mox

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

  describe "translating" do
    setup :verify_on_exit!

    test "fills the other languages from Swedish", %{conn: conn} do
      expect(Edenflowers.External.ClaudeAPI.Mock, :translate, fn %{"name" => "Höstkransar"}, "sv-FI" ->
        {:ok,
         %{
           "en-GB" => %{"name" => "Autumn wreaths", "description" => "Make a wreath."},
           "fi" => %{"name" => "Syysseppeleet", "description" => "Tee seppele."}
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/new")

      view
      |> form("#course-form", form: %{translations: %{"sv-FI": %{name: "Höstkransar", description: "Gör en krans."}}})
      |> render_change()

      view |> element("button[phx-value-from='sv-FI']") |> render_click()
      html = render_async(view)

      assert html =~ "Autumn wreaths"
      assert html =~ "Syysseppeleet"
      assert html =~ "Tee seppele."
      assert html =~ "Gör en krans."
    end

    test "translates a saved course without editing it first", %{conn: conn} do
      course = generate(course(name: "Autumn wreaths"))

      expect(Edenflowers.External.ClaudeAPI.Mock, :translate, fn %{"name" => "Autumn wreaths"}, "en-GB" ->
        {:ok,
         %{
           "sv-FI" => %{"name" => "Höstkransar", "description" => ""},
           "fi" => %{"name" => "Syysseppeleet", "description" => ""}
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

      view |> element("button[phx-value-from='en-GB']") |> render_click()
      render_async(view)
      view |> form("#course-form") |> render_submit()

      saved = Ash.get!(Course, course.id, authorize?: false)
      assert saved.name == "Autumn wreaths"
      assert saved.translations."sv-FI".name == "Höstkransar"
      assert saved.translations.fi.name == "Syysseppeleet"
    end

    test "shows an error when Claude fails", %{conn: conn} do
      expect(Edenflowers.External.ClaudeAPI.Mock, :translate, fn _, _ -> {:error, :timeout} end)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/new")
      view |> form("#course-form", form: %{name: "Autumn wreaths"}) |> render_change()
      view |> element("button[phx-value-from='en-GB']") |> render_click()

      assert render_async(view) =~ "Translation failed"
    end
  end

  defp photo(name), do: %{name: name, content: "jpeg bytes", type: "image/jpeg"}
end
