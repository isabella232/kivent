from kivy.properties import StringProperty, BooleanProperty, ObjectProperty
from math import radians
from xml.dom.minidom import parse as parse_xml
from kivy.core.image import Image as CoreImage
from libc.math cimport trunc, M_PI_2
from kivy.graphics import Fbo, Rectangle, Color, RenderContext, Mesh
from kivy.graphics.opengl import (glEnable, glBlendFunc, GL_SRC_ALPHA, GL_ONE, 
GL_ZERO, GL_SRC_COLOR, GL_ONE_MINUS_SRC_COLOR, GL_ONE_MINUS_SRC_ALPHA, 
GL_DST_ALPHA, GL_ONE_MINUS_DST_ALPHA, GL_DST_COLOR, GL_ONE_MINUS_DST_COLOR,
glDisable)



BLEND_FUNC = {
            0: GL_ZERO,
            1: GL_ONE,
            0x300: GL_SRC_COLOR,
            0x301: GL_ONE_MINUS_SRC_COLOR,
            0x302: GL_SRC_ALPHA,
            0x303: GL_ONE_MINUS_SRC_ALPHA,
            0x304: GL_DST_ALPHA,
            0x305: GL_ONE_MINUS_DST_ALPHA,
            0x306: GL_DST_COLOR,
            0x307: GL_ONE_MINUS_DST_COLOR,
            }

class ParticleManager(GameSystem):
    system_id = StringProperty('particle_manager')
    current_number_of_particles = NumericProperty(0)
    max_number_particles = NumericProperty(100)
    position_data_from = StringProperty('cymunk-physics')
    render_information_from = StringProperty('physics_renderer')
    shader_source = StringProperty('pointshader.glsl')
    updateable = BooleanProperty(True)
    number_of_effects = NumericProperty(0)
    particle_update_time = NumericProperty(1./20.)
    blend_factor_source = NumericProperty(GL_SRC_ALPHA)
    blend_factor_dest = NumericProperty(GL_ONE)
    atlas_dir = StringProperty(None)
    atlas = StringProperty(None)
    reset_blend_factor_source = NumericProperty(GL_SRC_ALPHA)
    reset_blend_factor_dest = NumericProperty(GL_ONE_MINUS_SRC_ALPHA)
    mesh = ObjectProperty(None, allownone=True)

    def __init__(self, **kwargs):
        self.canvas = RenderContext(use_parent_projection=True)
        if 'shader_source' in kwargs:
            self.canvas.shader.source = kwargs.get('shader_source')
        super(ParticleManager, self).__init__(**kwargs)
        with self.canvas.before:
            Callback(self._set_blend_func)
        with self.canvas.after:
            Callback(self._reset_blend_func)
        self.particle_configs = {}
        self.particle_textures = {}
        self.particles = []
        self.unused_particle_effects = []
        Clock.schedule_once(self.init_particles)

    def on_shader_source(self, instance, value):
        self.canvas.shader.source = value

    def on_atlas(self, instance, value):
        if value and self.atlas_dir:
            self.uv_dict = self.return_uv_coordinates(
                value + '.atlas', value + '-0.png', self.atlas_dir)

    def on_atlas_dir(self, instance, value):
        if value and self.atlas:
            self.uv_dict = self.return_uv_coordinates(
                self.atlas + '.atlas', self.atlas + '-0.png', value)

    def return_uv_coordinates(self, atlas_name, atlas_page, atlas_dir):
        uv_dict = {}
        uv_dict['main_texture'] = atlas = CoreImage(
            atlas_dir + atlas_page).texture
        size = atlas.size
        uv_dict['atlas_size'] = atlas_size = (float(size[0]), float(size[1]))
        w, h = atlas_size
        with open(atlas_dir + atlas_name, 'r') as fd:
            atlas_data = json.load(fd)
        atlas_content = atlas_data[atlas_page]
        for texture_name in atlas_content:
            data = atlas_content[texture_name]
            x1, y1 = data[0], data[1]
            x2, y2 = x1 + data[2], y1 + data[3]
            uv_dict[
                texture_name] = x1/w, 1.-y1/h, x2/w, 1.-y2/h, data[2], data[3]
        return uv_dict

    def _set_blend_func(self, instruction):
        glBlendFunc(self.blend_factor_source, self.blend_factor_dest)

    def _reset_blend_func(self, instruction):
        glBlendFunc(self.reset_blend_factor_source, 
            self.reset_blend_factor_dest)

    def init_particles(self, dt):
        particles = self.particles
        entities = self.gameworld.entities
        for x in xrange(self.max_number_particles):
            entity_id = self.gameworld.init_entity({}, [])
            entities[entity_id]['particle_manager'] = {'particle': Particle()}
            self.particles.append(entity_id)

    def free_particle(self, entity_id):
        self.particles.append(entity_id)

    def on_max_number_particles(self, instance, value):
        pass

    def on_current_number_of_particles(self, instance, value):
        pass

    def load_particle_config(self, config):
        config_str = config
        config = parse_xml(config)
        particle_configs = self.particle_configs
        particle_textures = self.particle_textures
        particle_configs[config_str] = particle_config = {}
        texture_str = self.parse_data(config, 'texture', 'name')
        particle_config['texture'] = texture_str
        particle_config['emitter_x_variance'] = float(self.parse_data(
            config, 'sourcePositionVariance', 'x'))
        particle_config['emitter_y_variance'] = float(self.parse_data(
            config, 'sourcePositionVariance', 'y'))
        particle_config['gravity_x'] = float(self.parse_data(
            config, 'gravity', 'x'))
        particle_config['gravity_y'] = float(self.parse_data(
            config,'gravity', 'y'))
        particle_config['emitter_type'] = int(self.parse_data(
            config, 'emitterType'))
        particle_config['max_num_particles'] = int(self.parse_data(
            config, 'maxParticles'))
        particle_config['life_span'] = max(0.01, float(self.parse_data(
            config, 'particleLifeSpan')))
        particle_config['life_span_variance'] = float(self.parse_data(
            config, 'particleLifespanVariance'))
        particle_config['start_size'] = float(self.parse_data(
            config, 'startParticleSize'))
        particle_config['start_size_variance'] = float(self.parse_data(
            config, 'startParticleSizeVariance'))
        particle_config['end_size'] = float(self.parse_data(
            config, 'finishParticleSize'))
        particle_config['end_size_variance'] = float(self.parse_data(
            config, 'FinishParticleSizeVariance'))
        particle_config['emit_angle'] = math.radians(float(self.parse_data(
            config, 'angle')))
        particle_config['emit_angle_variance'] = math.radians(float(self.parse_data(
            config, 'angleVariance')))
        particle_config['start_rotation'] = math.radians(float(self.parse_data(
            config, 'rotationStart')))
        particle_config['start_rotation_variance'] = math.radians(float(self.parse_data(
            config, 'rotationStartVariance')))
        particle_config['end_rotation'] = math.radians(float(self.parse_data(
            config, 'rotationEnd')))
        particle_config['end_rotation_variance'] = math.radians(float(self.parse_data(
            config, 'rotationEndVariance')))
        particle_config['speed'] = float(self.parse_data(
            config, 'speed'))
        particle_config['speed_variance'] = float(self.parse_data(
            config, 'speedVariance'))
        particle_config['radial_acceleration'] = float(self.parse_data(
            config, 'radialAcceleration'))
        particle_config['radial_acceleration_variance'] = float(self.parse_data(
            config, 'radialAccelVariance'))
        particle_config['tangential_acceleration'] = float(self.parse_data(
            config, 'tangentialAcceleration'))
        particle_config['tangential_acceleration_variance'] = float(self.parse_data(
            config, 'tangentialAccelVariance'))
        particle_config['max_radius'] = float(self.parse_data(
            config, 'maxRadius'))
        particle_config['max_radius_variance'] = float(self.parse_data(
            config, 'maxRadiusVariance'))
        particle_config['min_radius'] = float(self.parse_data(
            config, 'minRadius'))
        particle_config['rotate_per_second'] = math.radians(float(self.parse_data(
            config, 'rotatePerSecond')))
        particle_config['rotate_per_second_variance'] = math.radians(float(self.parse_data(
            config, 'rotatePerSecondVariance')))
        particle_config['start_color'] = self.parse_color(
            config, 'startColor')
        particle_config['start_color_variance'] = self.parse_color(
            config, 'startColorVariance')
        particle_config['end_color'] = self.parse_color(
            config, 'finishColor')
        particle_config['end_color_variance'] = self.parse_color(
            config, 'finishColorVariance')
        particle_config['blend_factor_source'] = self.parse_blend(
            config, 'blendFuncSource')
        particle_config['blend_factor_dest'] = self.parse_blend(
            config, 'blendFuncDestination')

    def parse_data(self, config, name, attribute='value'):
        return config.getElementsByTagName(
            name)[0].getAttribute(attribute)

    def parse_color(self, config, name):
        return [
            float(self.parse_data(config, name, 'red')), 
            float(self.parse_data(config, name, 'green')), 
            float(self.parse_data(config, name, 'blue')), 
            float(self.parse_data(config, name, 'alpha')),
            ]

    def parse_blend(self, config, name):
        value = int(self.parse_data(config, name))
        return BLEND_FUNC[value]

    def get_particle_system(self):
        if self.unused_particle_effects:
            return self.unused_particle_effects.pop()
        else:
            self.number_of_effects += 1
            return ParticleEmitter(
            group_id=self.number_of_effects,
            config=None,
            gameworld=self.gameworld,
            particle_manager=self)

    def load_particle_system_from_dict(self, config):
        config_dict = self.particle_configs[config]
        if 'cymunk-physics' in self.gameworld.systems:
            physics_system_friction = self.gameworld.systems['cymunk-physics'].damping
        else:
            physics_system_friction = 1.0
        self.current_number_of_particles += config_dict[
            'max_num_particles']
        particle_system = self.get_particle_system()
        particle_system.max_num_particles = config_dict[
            'max_num_particles']
        particle_system.adjusted_num_particles = config_dict[
            'max_num_particles']
        particle_system.life_span = config_dict['life_span']
        particle_system.texture = config_dict['texture']
        particle_system.texture_path = config_dict['texture']
        particle_system.life_span_variance = config_dict['life_span_variance']
        particle_system.start_size = config_dict['start_size']
        particle_system.start_size_variance = config_dict[
            'start_size_variance']
        particle_system.end_size = config_dict['end_size']
        particle_system.end_size_variance = config_dict['end_size_variance']
        particle_system.emit_angle = config_dict['emit_angle']
        particle_system.emit_angle_variance = config_dict[
            'emit_angle_variance']
        particle_system.start_rotation = config_dict['start_rotation']
        particle_system.start_rotation_variance = config_dict[
            'start_rotation_variance']
        particle_system.end_rotation = config_dict['end_rotation']
        particle_system.end_rotation_variance = config_dict[
            'end_rotation_variance']
        particle_system.emitter_x_variance = config_dict['emitter_x_variance']
        particle_system.emitter_y_variance = config_dict['emitter_y_variance']
        particle_system.gravity_x = config_dict['gravity_x']
        particle_system.gravity_y = config_dict['gravity_y']
        particle_system.speed = config_dict['speed']
        particle_system.speed_variance = config_dict['speed_variance']
        particle_system.radial_acceleration = config_dict[
            'radial_acceleration']
        particle_system.radial_acceleration_variance = config_dict[
            'radial_acceleration_variance']
        particle_system.tangential_acceleration = config_dict[
            'tangential_acceleration']
        particle_system.tangential_acceleration_variance = config_dict[
            'tangential_acceleration_variance']
        particle_system.max_radius = config_dict['max_radius']
        particle_system.max_radius_variance = config_dict[
            'max_radius_variance']
        particle_system.min_radius = config_dict['min_radius']
        particle_system.rotate_per_second = config_dict['rotate_per_second']
        particle_system.rotate_per_second_variance = config_dict[
            'rotate_per_second_variance']
        particle_system.start_color = config_dict['start_color']
        particle_system.start_color_variance = config_dict[
            'start_color_variance']
        particle_system.end_color = config_dict['end_color']
        particle_system.end_color_variance = config_dict['end_color_variance']
        particle_system.blend_factor_source =config_dict[
            'blend_factor_source']
        particle_system.blend_factor_dest = config_dict['blend_factor_dest']
        particle_system.emitter_type = config_dict['emitter_type']
        particle_system.update_interval = self.particle_update_time
        particle_system.friction = (1.0 - physics_system_friction)
        return particle_system
        
    def generate_component_data(self, dict entity_component_dict):
        for particle_effect in entity_component_dict:
            config = entity_component_dict[particle_effect]['particle_file']
            if not config in self.particle_configs:
                self.load_particle_config(config)
            entity_component_dict[particle_effect]['particle_system'] = (
                particle_system) = self.load_particle_system_from_dict(config)
            entity_component_dict[particle_effect]['particle_system_on'] = False
        return entity_component_dict

    def remove_entity(self, entity_id):
        cdef list entities = self.gameworld.entities
        cdef str system_id = self.system_id
        cdef dict entity = entities[entity_id]
        cdef object particle_system 
        cdef dict particle_systems
        particle_systems = entity[self.system_id]
        unused_effects_append = self.unused_particle_effects.append
        for particle_effect in particle_systems:
            particle_system = particle_systems[particle_effect]['particle_system']
            particle_system.free_all_particles()
            self.current_number_of_particles -= particle_system.max_num_particles
            unused_effects_append(particle_system)
        super(ParticleManager, self).remove_entity(entity_id)

    def draw_mesh(self, list particles):
        vertex_format = [
            ('vPosition', 2, 'float'),
            ('vTexCoords0', 2, 'float'),
            ('vCenter', 2, 'float'),
            ('vRotation', 1, 'float'),
            ('vColor', 4, 'float'),
            ('vScale', 1, 'float')
            ]
        cdef list indices = []
        cdef dict uv_dict = self.uv_dict
        ie = indices.extend
        cdef list vertices = []
        e = vertices.extend
        for entity_n in range(len(particles)):
            offset = 4 * entity_n
            ie([0 + offset, 1 + offset, 
                2 + offset, 2 + offset,
                3 + offset, 0 + offset])
        for particle in particles:
            tex_choice = particle.texture
            x, y = particle.x, particle.y
            rotate = particle.rotation
            uv = uv_dict[tex_choice]
            color = particle.color
            w, h = uv[4], uv[5]
            scale = particle.scale/w
            x0, y0 = uv[0], uv[1]
            x1, y1 = uv[2], uv[3]
            vertex1 = [-w, -h, x0, y0, x, y, rotate,
                color[0], color[1], color[2], color[3], scale]
            vertex2 = [w, -h, x1, y0, x, y, rotate,
                color[0], color[1], color[2], color[3], scale]
            vertex3 = [w, h, x1, y1, x, y, rotate,
                color[0], color[1], color[2], color[3], scale]
            vertex4 = [-w, h, x0, y1, x, y, rotate,
                color[0], color[1], color[2], color[3], scale]
            verts = [vertex1, vertex2, vertex3, vertex4]
            for vert in verts:
                e(vert)
        mesh = self.mesh
        if mesh == None:
            with self.canvas:
                self.mesh = Mesh(
                    indices=indices,
                    vertices=vertices,
                    fmt=vertex_format,
                    mode='triangles',
                    texture=uv_dict['main_texture'])
        else:
            mesh.vertices = vertices
            mesh.indices = indices

    def update(self, dt):
        cdef dict systems = self.gameworld.systems
        cdef list entities = self.gameworld.entities
        cdef str render_information_from = self.render_information_from
        cdef str position_data_from = self.position_data_from
        cdef str system_data_from = self.system_id
        cdef dict entity
        cdef dict particle_systems
        cdef object particle_system
        cdef list particles_to_render = []
        eparticles = particles_to_render.extend
        cdef list particles = self.particles
        for entity_id in self.entity_ids:
            entity = entities[entity_id]
            particle_systems = entity[system_data_from]
            calculate_particle_offset = self.calculate_particle_offset
            for particle_effect in particle_systems:
                particle_system = particle_systems[
                    particle_effect]['particle_system']
                if entity[render_information_from]['on_screen']:
                    if particle_systems[particle_effect]['particle_system_on']:
                        particle_system.pos = calculate_particle_offset(
                            entity_id, particle_effect)
                        particle_system.emit_angle = entity[
                            position_data_from]['angle'] + 3. * M_PI_2
                        time_between_particles = (
                            1.0 / particle_system.emission_rate)
                        particle_system.frame_time += dt
                        eparticles(particle_system.update(dt))
                        number_of_updates = trunc(
                            particle_system.frame_time / time_between_particles)
                        particle_system.frame_time -= (
                            time_between_particles * number_of_updates)
                        for x in xrange(int(number_of_updates)):
                            if particles != []:
                                particle = particles.pop()
                                particle_system.receive_particle(particle)
                    else:
                        if particle_system.particles != []:
                            particle_system.free_all_particles()
                else:
                    if particle_system.particles != []:
                        particle_system.free_all_particles()
        self.draw_mesh(particles_to_render)

    def calculate_particle_offset(self, entity_id, particle_effect):
        cdef dict entity = self.gameworld.entities[entity_id]
        cdef dict position_data = entity[self.position_data_from]
        cdef dict system_data = entity[self.system_id]
        cdef int offset = system_data[particle_effect]['offset']
        cdef tuple effect_pos
        pos = position_data['position']
        if offset != 0.:
            unit_vector = position_data['unit_vector']
            effect_pos = (pos[0] - offset * unit_vector[0], 
                pos[1] - offset * unit_vector[1])
        else:
            effect_pos = (pos[0], pos[1])
        return effect_pos
