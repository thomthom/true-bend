#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'testup/testcase'
require_relative '../lib/test_utilities'

require 'tt_truebend/gl/face_colors'

module TT::Plugins::TrueBend
  module Tests
    class TC_FaceColors < TestUp::TestCase

      include TrueBendTestUtilities

      RED = [200, 60, 40].freeze
      BLUE = [60, 110, 200].freeze
      GREEN = [40, 160, 70].freeze

      FRONT = [250, 240, 230].freeze
      BACK = [100, 110, 120].freeze
      BACKGROUND = [10, 20, 30].freeze

      # The rendering options the tests change, with the values they start
      # each test with.
      OPTIONS = {
        'RenderMode'           => 2,
        'DisplayColorByLayer'  => false,
        'MaterialTransparency' => true,
        'FaceFrontColor'       => Sketchup::Color.new(*FRONT),
        'FaceBackColor'        => Sketchup::Color.new(*BACK),
        'BackgroundColor'      => Sketchup::Color.new(*BACKGROUND),
      }.freeze

      def setup
        model = start_with_empty_model
        options = model.rendering_options
        @original_options = {}
        OPTIONS.each { |key, value|
          @original_options[key] = options[key]
          options[key] = value
        }
      end

      def teardown
        options = Sketchup.active_model.rendering_options
        @original_options.each { |key, value| options[key] = value }
      end


      # @param [String] name
      # @param [Array<Integer>] rgb
      # @param [Float] alpha
      # @return [Sketchup::Material]
      def material(name, rgb, alpha = 1.0)
        material = Sketchup.active_model.materials.add(name)
        material.color = Sketchup::Color.new(*rgb)
        material.alpha = alpha
        material
      end

      # @param [Sketchup::Entities] entities
      # @return [Sketchup::Face]
      def add_face(entities = Sketchup.active_model.entities)
        entities.add_face([0, 0, 0], [10.mm, 0, 0], [10.mm, 10.mm, 0], [0, 10.mm, 0])
      end

      # @param [Array<Integer>] expected Red, green, blue and alpha.
      # @param [Sketchup::Color] color
      # @param [String] message
      def assert_color(expected, color, message = nil)
        assert_kind_of(Sketchup::Color, color, message)
        assert_equal(expected, color.to_a, message)
      end


      def test_colors_are_the_materials_of_the_front_and_the_back
        face = add_face
        face.material = material('Red', RED)
        face.back_material = material('Blue', BLUE)

        front, back = FaceColors.new(Sketchup.active_model).colors_of(face)

        assert_color(RED + [255], front, 'Front')
        assert_color(BLUE + [255], back, 'Back')
      end

      def test_colors_without_a_material_are_the_face_colors_of_the_style
        face = add_face

        front, back = FaceColors.new(Sketchup.active_model).colors_of(face)

        assert_color(FRONT + [255], front, 'Front')
        assert_color(BACK + [255], back, 'Back')
      end

      def test_colors_without_a_material_are_the_material_of_the_instance
        group = Sketchup.active_model.entities.add_group
        face = add_face(group.entities)
        group.material = material('Green', GREEN)
        face_colors = FaceColors.new(Sketchup.active_model)

        front, back = face_colors.colors_of(face, face_colors.inherit(group))

        assert_color(GREEN + [255], front, 'Front')
        assert_color(GREEN + [255], back, 'Back')
      end

      def test_colors_inherit_through_an_instance_without_a_material
        outer = Sketchup.active_model.entities.add_group
        inner = outer.entities.add_group
        face = add_face(inner.entities)
        outer.material = material('Green', GREEN)
        face_colors = FaceColors.new(Sketchup.active_model)

        inherited = face_colors.inherit(inner, face_colors.inherit(outer))
        front, back = face_colors.colors_of(face, inherited)

        assert_color(GREEN + [255], front, 'Front')
        assert_color(GREEN + [255], back, 'Back')
      end

      def test_colors_prefer_the_nearest_instance_with_a_material
        outer = Sketchup.active_model.entities.add_group
        inner = outer.entities.add_group
        face = add_face(inner.entities)
        outer.material = material('Green', GREEN)
        inner.material = material('Blue', BLUE)
        face_colors = FaceColors.new(Sketchup.active_model)

        front, = face_colors.colors_of(face, face_colors.inherit(inner, face_colors.inherit(outer)))

        assert_color(BLUE + [255], front)
      end

      def test_colors_prefer_the_material_of_the_face_over_the_instance
        group = Sketchup.active_model.entities.add_group
        face = add_face(group.entities)
        face.material = material('Red', RED)
        group.material = material('Green', GREEN)
        face_colors = FaceColors.new(Sketchup.active_model)

        front, back = face_colors.colors_of(face, face_colors.inherit(group))

        assert_color(RED + [255], front, 'Front')
        assert_color(GREEN + [255], back, 'Back')
      end

      def test_colors_are_never_more_opaque_than_the_given_opacity
        face = add_face
        face.material = material('Red', RED)

        front, back = FaceColors.new(Sketchup.active_model, 0.5).colors_of(face)

        assert_color(RED + [127], front, 'A material')
        assert_color(BACK + [127], back, 'A colour of the style')
      end

      def test_colors_of_a_transparent_material_are_more_transparent
        face = add_face
        face.material = material('Glass', BLUE, 0.5)

        front, = FaceColors.new(Sketchup.active_model, 0.5).colors_of(face)

        assert_color(BLUE + [63], front)
      end

      def test_colors_ignore_the_opacity_of_materials_when_the_style_does
        Sketchup.active_model.rendering_options['MaterialTransparency'] = false
        face = add_face
        face.material = material('Glass', BLUE, 0.5)

        front, = FaceColors.new(Sketchup.active_model, 0.5).colors_of(face)

        assert_color(BLUE + [127], front)
      end

      def test_colors_monochrome_style_ignores_materials
        Sketchup.active_model.rendering_options['RenderMode'] = FaceColors::MONOCHROME
        group = Sketchup.active_model.entities.add_group
        face = add_face(group.entities)
        face.material = material('Red', RED)
        group.material = material('Green', GREEN)
        face_colors = FaceColors.new(Sketchup.active_model)

        front, back = face_colors.colors_of(face, face_colors.inherit(group))

        assert_color(FRONT + [255], front, 'Front')
        assert_color(BACK + [255], back, 'Back')
      end

      def test_colors_hidden_line_style_is_the_background_color
        Sketchup.active_model.rendering_options['RenderMode'] = FaceColors::HIDDEN_LINE
        face = add_face
        face.material = material('Red', RED)

        front, back = FaceColors.new(Sketchup.active_model).colors_of(face)

        assert_color(BACKGROUND + [255], front, 'Front')
        assert_color(BACKGROUND + [255], back, 'Back')
      end

      def test_colors_by_tag_is_the_color_of_the_tag_of_the_face
        model = Sketchup.active_model
        model.rendering_options['DisplayColorByLayer'] = true
        tag = model.layers.add('Tagged')
        tag.color = Sketchup::Color.new(*GREEN)
        face = add_face
        face.material = material('Red', RED)
        face.layer = tag

        front, back = FaceColors.new(model).colors_of(face)

        assert_color(GREEN + [255], front, 'Front')
        assert_color(GREEN + [255], back, 'Back')
      end

      def test_colors_by_tag_untagged_face_has_the_color_of_the_tag_of_the_instance
        model = Sketchup.active_model
        model.rendering_options['DisplayColorByLayer'] = true
        tag = model.layers.add('Tagged')
        tag.color = Sketchup::Color.new(*GREEN)
        group = model.entities.add_group
        face = add_face(group.entities)
        group.layer = tag
        face_colors = FaceColors.new(model)

        front, = face_colors.colors_of(face, face_colors.inherit(group))

        assert_color(GREEN + [255], front)
      end

      def test_colors_by_tag_tagged_face_keeps_its_own_tag_in_a_tagged_instance
        model = Sketchup.active_model
        model.rendering_options['DisplayColorByLayer'] = true
        group_tag = model.layers.add('Group')
        group_tag.color = Sketchup::Color.new(*GREEN)
        face_tag = model.layers.add('Face')
        face_tag.color = Sketchup::Color.new(*BLUE)
        group = model.entities.add_group
        face = add_face(group.entities)
        group.layer = group_tag
        face.layer = face_tag
        face_colors = FaceColors.new(model)

        front, = face_colors.colors_of(face, face_colors.inherit(group))

        assert_color(BLUE + [255], front)
      end

      # Triangles are grouped by colour with the colour object as the key.
      def test_colors_equal_colors_are_the_same_object
        entities = Sketchup.active_model.entities
        face1 = add_face(entities.add_group.entities)
        face2 = add_face(entities.add_group.entities)
        face1.material = material('Red', RED)
        face2.material = material('Also Red', RED)
        face_colors = FaceColors.new(Sketchup.active_model)

        assert_same(face_colors.colors_of(face1)[0], face_colors.colors_of(face2)[0])
      end

      def test_fill_is_false_only_for_the_wireframe_style
        options = Sketchup.active_model.rendering_options
        [FaceColors::HIDDEN_LINE, 2, FaceColors::MONOCHROME].each { |mode|
          options['RenderMode'] = mode
          assert(FaceColors.new(Sketchup.active_model).fill?, "Render mode #{mode}")
        }

        options['RenderMode'] = FaceColors::WIREFRAME

        refute(FaceColors.new(Sketchup.active_model).fill?, 'Wireframe')
      end

    end # class
  end # module
end # module
