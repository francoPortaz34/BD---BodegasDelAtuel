DROP SCHEMA IF EXISTS bodegas CASCADE;
CREATE SCHEMA bodegas;
SET search_path TO bodegas;

--tipos enumerados
CREATE TYPE tipo_vino AS ENUM ('tinto', 'blanco', 'rosado', 'espumante');
CREATE TYPE tipo_cepa AS ENUM('tinta', 'blanca');
CREATE TYPE estado_movimiento AS ENUM ('en_confeccion', 'terminado', 'procesado');
CREATE TYPE dia_semana AS ENUM ('lunes', 'martes', 'miercoles', ' jueves', 'viernes', 'sabado', 'domingo');
CREATE TYPE tipo_documento AS ENUM ('DNI', 'CUIT', 'CUIL', 'PASAPORTE');

--dominios
CREATE DOMAIN dom_cuit AS CHAR(11) CHECK (VALUE ~ '^[0-9]{11}$');
CREATE DOMAIN dom_dinero AS DECIMAL(12,2) CHECK (VALUE >= 0);
CREATE DOMAIN dom_porcentaje AS DECIMAL(5,2) CHECK (VALUE BETWEEN 0 AND 100);
CREATE DOMAIN dom_cantidad AS INTEGER CHECK (VALUE >= 0);
CREATE DOMAIN dom_email AS VARCHAR(100) CHECK (VALUE LIKE '%_@_%._%');

--tablas
CREATE TABLE encargado (
   id_encargado SERIAL NOT NULL,
   nombre VARCHAR(50) NOT NULL,
   apellido VARCHAR(50) NOT NULL,
   dni VARCHAR(50) NOT NULL,
   CONSTRAINT pk_encargado PRIMARY KEY (id_encargado),
   CONSTRAINT uq_encargado_dni UNIQUE (dni)
);

CREATE TABLE departamento (
   id_departamento SERIAL NOT NULL,
   nombre VARCHAR (80) NOT NULL,
   provincia VARCHAR (50) NOT NULL,
   CONSTRAINT pk_departamento PRIMARY KEY (id_departamento)
);

CREATE TABLE cepa (
   id_cepa SERIAL NOT NULL,
   nombre VARCHAR(50) NOT NULL,
   tipo tipo_cepa NOT NULL,
   CONSTRAINT pk_cepa PRIMARY KEY (id_cepa),
   CONSTRAINT uq_cepa_nombre UNIQUE (nombre)
);

CREATE TABLE bodega (
    id_bodega SERIAL NOT NULL,
    cuit dom_cuit NOT NULL,
    razon_social VARCHAR(100) NOT NULL,
    calle VARCHAR(80) NOT NULL,
    numero VARCHAR(10) NOT NULL,
    CONSTRAINT pk_bodega PRIMARY KEY (id_bodega),
    CONSTRAINT uq_bodega_cuit UNIQUE (cuit)
);

CREATE TABLE maridaje (
    id_maridaje SERIAL NOT NULL,
    nombre VARCHAR(60) NOT NULL,
    temperatura_sugerida DECIMAL(4,1) NOT NULL,
    CONSTRAINT pk_maridaje PRIMARY KEY (id_maridaje),
    CONSTRAINT uq_maridaje_nombre UNIQUE (nombre)
);

CREATE TABLE tipo_cliente (
    id_tipo_cliente SERIAL NOT NULL,
    nombre VARCHAR(20) NOT NULL,
    porcentaje_descuento  dom_porcentaje NOT NULL,
    CONSTRAINT pk_tipo_cliente PRIMARY KEY (id_tipo_cliente),
    CONSTRAINT uq_tipo_cliente_nombre UNIQUE (nombre)
);

CREATE TABLE transportista (
    id_transportista SERIAL NOT NULL,
    cod_transporte VARCHAR(20) NOT NULL,
    razon_social VARCHAR(100) NOT NULL,
    cuit dom_cuit NOT NULL,
    calle VARCHAR(80) NOT NULL,
    numero VARCHAR(10) NOT NULL,
    CONSTRAINT pk_transportista PRIMARY KEY (id_transportista),
    CONSTRAINT uq_transportista_cod UNIQUE (cod_transporte),
    CONSTRAINT uq_transportista_cuit UNIQUE (cuit)
);

CREATE TABLE localidad (
    id_localidad SERIAL NOT NULL,
    cod_postal CHAR(4) NOT NULL,
    nombre VARCHAR(80) NOT NULL,
    provincia VARCHAR(50)  NOT NULL,
    id_encargado INTEGER NOT NULL,
    CONSTRAINT pk_localidad PRIMARY KEY (id_localidad),
    CONSTRAINT uq_localidad_encargado UNIQUE (id_encargado),
    CONSTRAINT fk_localidad_encargado FOREIGN KEY (id_encargado) REFERENCES encargado (id_encargado)
);

CREATE TABLE finca (
    id_finca SERIAL NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    sup_total_ha DECIMAL(10,2) NOT NULL,
    id_departamento INTEGER NOT NULL,
    CONSTRAINT pk_finca PRIMARY KEY (id_finca),
    CONSTRAINT fk_finca_departamento FOREIGN KEY (id_departamento) REFERENCES departamento (id_departamento)
);

CREATE TABLE vino (
    id_vino SERIAL NOT NULL,
    cod_vino VARCHAR(20) NOT NULL,
    nombre_comercial VARCHAR(100) NOT NULL,
    tipo tipo_vino NOT NULL,
    anada SMALLINT NOT NULL,
    presentacion_ml SMALLINT NOT NULL,
    graduacion_alcoholica DECIMAL(4,2) NOT NULL,
    precio_venta dom_dinero NOT NULL,
    id_bodega INTEGER NOT NULL,
    CONSTRAINT pk_vino PRIMARY KEY (id_vino),
    CONSTRAINT uq_vino_cod UNIQUE (cod_vino),
    CONSTRAINT fk_vino_bodega FOREIGN KEY (id_bodega) REFERENCES bodega (id_bodega)
);

CREATE TABLE sala_de_ventas (
    id_sala SERIAL NOT NULL,
    calle VARCHAR(80) NOT NULL,
    numero VARCHAR(10) NOT NULL,
    dia_cierre_semanal dia_semana NOT NULL,
    id_localidad INTEGER NOT NULL,
    CONSTRAINT pk_sala_de_ventas PRIMARY KEY (id_sala),
    CONSTRAINT fk_sala_localidad FOREIGN KEY (id_localidad) REFERENCES localidad (id_localidad)
);

CREATE TABLE cliente (
    id_cliente SERIAL NOT NULL,
    nombre_o_razon_social VARCHAR(100) NOT NULL,
    tipo_documento tipo_documento NOT NULL,
    num_documento VARCHAR(20) NOT NULL,
    calle VARCHAR(80) NOT NULL,
    numero VARCHAR(10) NOT NULL,
    fecha_alta DATE NOT NULL,
    id_localidad INTEGER NOT NULL,
    id_tipo_cliente INTEGER NOT NULL,
    CONSTRAINT pk_cliente PRIMARY KEY (id_cliente),
    CONSTRAINT fk_cliente_localidad FOREIGN KEY (id_localidad) REFERENCES localidad (id_localidad),
    CONSTRAINT fk_cliente_tipo FOREIGN KEY (id_tipo_cliente) REFERENCES tipo_cliente (id_tipo_cliente)
);

CREATE TABLE parcela (
    id_finca INTEGER NOT NULL,
    num_parcela SMALLINT NOT NULL,
    superficie DECIMAL(8,2) NOT NULL,
    anio_plantacion SMALLINT NOT NULL,
    id_cepa INTEGER NOT NULL,
    CONSTRAINT pk_parcela PRIMARY KEY (id_finca, num_parcela),
    CONSTRAINT fk_parcela_finca FOREIGN KEY (id_finca) REFERENCES finca (id_finca),
    CONSTRAINT fk_parcela_cepa FOREIGN KEY (id_cepa) REFERENCES cepa (id_cepa)
);

CREATE TABLE vino_cepa (
    id_vino INTEGER NOT NULL,
    id_cepa INTEGER NOT NULL,
    porcentaje_corte dom_porcentaje NOT NULL,
    CONSTRAINT pk_vino_cepa PRIMARY KEY (id_vino, id_cepa),
    CONSTRAINT fk_vino_cepa_vino FOREIGN KEY (id_vino) REFERENCES vino (id_vino),
    CONSTRAINT fk_vino_cepa_cepa FOREIGN KEY (id_cepa) REFERENCES cepa (id_cepa)
);

CREATE TABLE vino_maridaje (
    id_vino INTEGER NOT NULL,
    id_maridaje INTEGER NOT NULL,
    CONSTRAINT pk_vino_maridaje PRIMARY KEY (id_vino, id_maridaje),
    CONSTRAINT fk_vino_maridaje_vino FOREIGN KEY (id_vino) REFERENCES vino (id_vino),
    CONSTRAINT fk_vino_maridaje_maridaje FOREIGN KEY (id_maridaje) REFERENCES maridaje (id_maridaje)
);

CREATE TABLE auditoria_precio (
    id_auditoria SERIAL NOT NULL,
    id_vino INTEGER NOT NULL,
    precio_anterior dom_dinero NOT NULL,
    precio_nuevo dom_dinero NOT NULL,
    fecha_hora TIMESTAMP NOT NULL,
    usuario VARCHAR(50) NOT NULL,
    CONSTRAINT pk_auditoria_precio PRIMARY KEY (id_auditoria),
    CONSTRAINT fk_auditoria_vino FOREIGN KEY (id_vino) REFERENCES vino (id_vino)
);

CREATE TABLE stock_deposito (
    id_vino INTEGER NOT NULL,
    cantidad dom_cantidad NOT NULL,
    CONSTRAINT pk_stock_deposito PRIMARY KEY (id_vino),
    CONSTRAINT fk_stock_deposito_vino FOREIGN KEY (id_vino) REFERENCES vino (id_vino)
);

CREATE TABLE transportista_email (
    id_transportista INTEGER NOT NULL,
    email dom_email NOT NULL,
    CONSTRAINT pk_transportista_email PRIMARY KEY (id_transportista, email),
    CONSTRAINT fk_email_transportista FOREIGN KEY (id_transportista) REFERENCES transportista (id_transportista)
);

CREATE TABLE transportista_telefono (
    id_transportista INTEGER NOT NULL,
    telefono VARCHAR(20) NOT NULL,
    CONSTRAINT pk_transportista_telefono PRIMARY KEY (id_transportista, telefono),
    CONSTRAINT fk_telefono_transportista FOREIGN KEY (id_transportista) REFERENCES transportista (id_transportista)
);

CREATE TABLE transportista_localidad (
    id_transportista INTEGER NOT NULL,
    id_localidad INTEGER NOT NULL,
    CONSTRAINT pk_transportista_localidad PRIMARY KEY (id_transportista, id_localidad),
    CONSTRAINT fk_tl_transportista FOREIGN KEY (id_transportista) REFERENCES transportista (id_transportista),
    CONSTRAINT fk_tl_localidad FOREIGN KEY (id_localidad) REFERENCES localidad (id_localidad)
);

CREATE TABLE ingreso (
    id_ingreso SERIAL NOT NULL,
    cod_ingreso VARCHAR(20) NOT NULL,
    fecha DATE NOT NULL,
    estado estado_movimiento NOT NULL,
    id_transportista INTEGER NOT NULL,
    id_bodega INTEGER NOT NULL,
    CONSTRAINT pk_ingreso PRIMARY KEY (id_ingreso),
    CONSTRAINT uq_ingreso_cod UNIQUE (cod_ingreso),
    CONSTRAINT fk_ingreso_transportista FOREIGN KEY (id_transportista) REFERENCES transportista (id_transportista),
    CONSTRAINT fk_ingreso_bodega FOREIGN KEY (id_bodega) REFERENCES bodega (id_bodega)
);

CREATE TABLE empleado (
    id_empleado SERIAL NOT NULL,
    cuit dom_cuit NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    fecha_ingreso DATE NOT NULL,
    salario dom_dinero NOT NULL,
    id_sala INTEGER NOT NULL,
    CONSTRAINT pk_empleado PRIMARY KEY (id_empleado),
    CONSTRAINT uq_empleado_cuit UNIQUE (cuit),
    CONSTRAINT fk_empleado_sala FOREIGN KEY (id_sala) REFERENCES sala_de_ventas (id_sala)
);

CREATE TABLE stock_sala (
    id_sala INTEGER NOT NULL,
    id_vino INTEGER NOT NULL,
    cantidad dom_cantidad NOT NULL,
    CONSTRAINT pk_stock_sala PRIMARY KEY (id_sala, id_vino),
    CONSTRAINT fk_stock_sala_sala FOREIGN KEY (id_sala) REFERENCES sala_de_ventas (id_sala),
    CONSTRAINT fk_stock_sala_vino FOREIGN KEY (id_vino) REFERENCES vino (id_vino)
);

CREATE TABLE transferencia (
    id_transferencia SERIAL NOT NULL,
    num_solicitud VARCHAR(20) NOT NULL,
    fecha_confeccion DATE NOT NULL,
    estado estado_movimiento NOT NULL,
    id_sala INTEGER NOT NULL,
    CONSTRAINT pk_transferencia PRIMARY KEY (id_transferencia),
    CONSTRAINT uq_transferencia_num UNIQUE (num_solicitud),
    CONSTRAINT fk_transferencia_sala FOREIGN KEY (id_sala) REFERENCES sala_de_ventas (id_sala)
);

CREATE TABLE socio (
    id_cliente INTEGER NOT NULL,
    CONSTRAINT pk_socio PRIMARY KEY (id_cliente),
    CONSTRAINT fk_socio_cliente FOREIGN KEY (id_cliente) REFERENCES cliente (id_cliente)
);

CREATE TABLE distribuidor (
    id_cliente INTEGER NOT NULL,
    zona_cobertura VARCHAR(100) NOT NULL,
    numero_habilitacion VARCHAR(30) NOT NULL,
    CONSTRAINT pk_distribuidor PRIMARY KEY (id_cliente),
    CONSTRAINT uq_distribuidor_habilitacion UNIQUE (numero_habilitacion),
    CONSTRAINT fk_distribuidor_cliente FOREIGN KEY (id_cliente) REFERENCES cliente (id_cliente)
);

CREATE TABLE exportador (
    id_cliente INTEGER NOT NULL,
    pais_destino_principal VARCHAR(60) NOT NULL,
    CONSTRAINT pk_exportador PRIMARY KEY (id_cliente),
    CONSTRAINT fk_exportador_cliente FOREIGN KEY (id_cliente) REFERENCES cliente (id_cliente)
);

CREATE TABLE lote_de_uva (
    id_lote_uva SERIAL NOT NULL,
    num_lote VARCHAR(20) NOT NULL,
    id_finca INTEGER NOT NULL,
    num_parcela SMALLINT NOT NULL,
    campania SMALLINT NOT NULL,
    fecha_cosecha DATE NOT NULL,
    kilos_cosechados DECIMAL(10,2) NOT NULL,
    id_bodega_entrega INTEGER NOT NULL,
    CONSTRAINT pk_lote_de_uva PRIMARY KEY (id_lote_uva),
    CONSTRAINT uq_lote_num UNIQUE (num_lote),
    CONSTRAINT fk_lote_parcela FOREIGN KEY (id_finca, num_parcela) REFERENCES parcela (id_finca, num_parcela),
    CONSTRAINT fk_lote_bodega FOREIGN KEY (id_bodega_entrega) REFERENCES bodega (id_bodega)
);

CREATE TABLE comprobante (
    id_comprobante SERIAL NOT NULL,
    num_comprobante VARCHAR(20) NOT NULL,
    fecha DATE NOT NULL,
    subtotal dom_dinero NOT NULL,
    descuento dom_dinero NOT NULL,
    total dom_dinero NOT NULL,
    id_cliente INTEGER NOT NULL,
    id_sala INTEGER NOT NULL,
    CONSTRAINT pk_comprobante PRIMARY KEY (id_comprobante),
    CONSTRAINT uq_comprobante_num UNIQUE (num_comprobante),
    CONSTRAINT fk_comprobante_cliente FOREIGN KEY (id_cliente) REFERENCES cliente (id_cliente),
    CONSTRAINT fk_comprobante_sala FOREIGN KEY (id_sala) REFERENCES sala_de_ventas (id_sala)
);

CREATE TABLE renglon_ingreso (
    id_renglon_ingreso SERIAL NOT NULL,
    id_ingreso INTEGER NOT NULL,
    id_vino INTEGER NOT NULL,
    cantidad_botellas dom_cantidad NOT NULL,
    CONSTRAINT pk_renglon_ingreso PRIMARY KEY (id_renglon_ingreso),
    CONSTRAINT fk_renglon_ingreso_ingreso FOREIGN KEY (id_ingreso) REFERENCES ingreso (id_ingreso),
    CONSTRAINT fk_renglon_ingreso_vino FOREIGN KEY (id_vino) REFERENCES vino (id_vino)
);

CREATE TABLE permiso_exportacion (
    id_permiso SERIAL NOT NULL,
    codigo VARCHAR(30) NOT NULL,
    fecha_emision DATE NOT NULL,
    fecha_vencimiento DATE NOT NULL,
    id_cliente INTEGER NOT NULL,
    CONSTRAINT pk_permiso_exportacion PRIMARY KEY (id_permiso),
    CONSTRAINT uq_permiso_codigo UNIQUE (codigo),
    CONSTRAINT fk_permiso_exportador FOREIGN KEY (id_cliente) REFERENCES exportador (id_cliente)
);

CREATE TABLE analisis_calidad (
    id_analisis SERIAL NOT NULL,
    id_lote_uva INTEGER NOT NULL,
    fecha DATE NOT NULL,
    grado_brix DECIMAL(4,1) NOT NULL,
    ph DECIMAL(4,2) NOT NULL,
    acidez_total DECIMAL(5,2) NOT NULL,
    CONSTRAINT pk_analisis_calidad PRIMARY KEY (id_analisis),
    CONSTRAINT fk_analisis_lote FOREIGN KEY (id_lote_uva) REFERENCES lote_de_uva (id_lote_uva)
);

CREATE TABLE detalle_comprobante (
    id_comprobante INTEGER NOT NULL,
    id_vino INTEGER NOT NULL,
    cantidad dom_cantidad NOT NULL,
    precio_unitario_venta dom_dinero NOT NULL,
    descuento_aplicado dom_porcentaje NOT NULL,
    subtotal_renglon dom_dinero NOT NULL,
    CONSTRAINT pk_detalle_comprobante PRIMARY KEY (id_comprobante, id_vino),
    CONSTRAINT fk_detalle_comprobante FOREIGN KEY (id_comprobante) REFERENCES comprobante (id_comprobante),
    CONSTRAINT fk_detalle_vino FOREIGN KEY (id_vino) REFERENCES vino (id_vino)
);

CREATE TABLE renglon_transferencia (
    id_renglon_transferencia SERIAL NOT NULL,
    id_transferencia INTEGER NOT NULL,
    id_vino INTEGER NOT NULL,
    cantidad_botellas dom_cantidad NOT NULL,
    CONSTRAINT pk_renglon_transferencia PRIMARY KEY (id_renglon_transferencia),
    CONSTRAINT fk_renglon_transf_transferencia FOREIGN KEY (id_transferencia) REFERENCES transferencia (id_transferencia),
    CONSTRAINT fk_renglon_transf_vino FOREIGN KEY (id_vino) REFERENCES vino (id_vino)
);