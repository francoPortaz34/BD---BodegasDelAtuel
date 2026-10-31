-- =====================================================================
-- 002_constraints.sql  -  Etapa 2: restricciones de integridad
-- =====================================================================
-- Completa el DDL de 001_esquema.sql con:
--   1. Corrección del ENUM dia_semana.
--   2. Acciones referenciales explícitas en TODAS las claves foráneas.
--   3. Restricciones UNIQUE adicionales.
--   4. Restricciones CHECK (incluye CHECK entre columnas).
--   5. Valores DEFAULT.
--
-- Importante: ningún CHECK usa CURRENT_DATE ni funciones no
-- determinísticas (se rompería al restaurar un backup). Las reglas que
-- dependen de la fecha actual o de otras filas van en triggers (005).
-- =====================================================================
SET search_path TO bodegas;


-- ---------------------------------------------------------------------
-- 1. Corrección del ENUM dia_semana
-- ---------------------------------------------------------------------
-- En 001 el valor quedó como ' jueves' (con un espacio adelante).
ALTER TYPE dia_semana RENAME VALUE ' jueves' TO 'jueves';


-- ---------------------------------------------------------------------
-- 2. Acciones referenciales de las claves foráneas
-- ---------------------------------------------------------------------
-- Criterio:
--   * ON UPDATE RESTRICT en todas: las PK son subrogadas (SERIAL) y no
--     cambian nunca; si alguien intenta cambiarlas, se rechaza.
--   * ON DELETE RESTRICT: no se borra un padre que tiene hijos. Es lo
--     que pide RN-14 para transportista, bodega y vino con movimientos,
--     y lo aplicamos también a catálogos y movimientos en general.
--   * ON DELETE CASCADE: sólo en filas que no tienen sentido sin su
--     cabecera (renglones, composición del vino, datos multivaluados,
--     subtipos de cliente, entidad débil parcela, análisis del lote).
--
-- En PostgreSQL no se puede "modificar" una FK: se borra y se vuelve a
-- crear con el mismo nombre, en una sola sentencia ALTER TABLE.

-- 2.a  RESTRICT: catálogos y datos maestros ---------------------------
ALTER TABLE localidad
    DROP CONSTRAINT fk_localidad_encargado,
    ADD  CONSTRAINT fk_localidad_encargado FOREIGN KEY (id_encargado)
         REFERENCES encargado (id_encargado) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE finca
    DROP CONSTRAINT fk_finca_departamento,
    ADD  CONSTRAINT fk_finca_departamento FOREIGN KEY (id_departamento)
         REFERENCES departamento (id_departamento) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE sala_de_ventas
    DROP CONSTRAINT fk_sala_localidad,
    ADD  CONSTRAINT fk_sala_localidad FOREIGN KEY (id_localidad)
         REFERENCES localidad (id_localidad) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE empleado
    DROP CONSTRAINT fk_empleado_sala,
    ADD  CONSTRAINT fk_empleado_sala FOREIGN KEY (id_sala)
         REFERENCES sala_de_ventas (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE cliente
    DROP CONSTRAINT fk_cliente_localidad,
    ADD  CONSTRAINT fk_cliente_localidad FOREIGN KEY (id_localidad)
         REFERENCES localidad (id_localidad) ON DELETE RESTRICT ON UPDATE RESTRICT,
    DROP CONSTRAINT fk_cliente_tipo,
    ADD  CONSTRAINT fk_cliente_tipo FOREIGN KEY (id_tipo_cliente)
         REFERENCES tipo_cliente (id_tipo_cliente) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE parcela
    DROP CONSTRAINT fk_parcela_cepa,
    ADD  CONSTRAINT fk_parcela_cepa FOREIGN KEY (id_cepa)
         REFERENCES cepa (id_cepa) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE vino_cepa
    DROP CONSTRAINT fk_vino_cepa_cepa,
    ADD  CONSTRAINT fk_vino_cepa_cepa FOREIGN KEY (id_cepa)
         REFERENCES cepa (id_cepa) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE vino_maridaje
    DROP CONSTRAINT fk_vino_maridaje_maridaje,
    ADD  CONSTRAINT fk_vino_maridaje_maridaje FOREIGN KEY (id_maridaje)
         REFERENCES maridaje (id_maridaje) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE transportista_localidad
    DROP CONSTRAINT fk_tl_localidad,
    ADD  CONSTRAINT fk_tl_localidad FOREIGN KEY (id_localidad)
         REFERENCES localidad (id_localidad) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE lote_de_uva
    DROP CONSTRAINT fk_lote_parcela,
    ADD  CONSTRAINT fk_lote_parcela FOREIGN KEY (id_finca, num_parcela)
         REFERENCES parcela (id_finca, num_parcela) ON DELETE RESTRICT ON UPDATE RESTRICT;

-- 2.b  RESTRICT: RN-14 (vino, bodega y transportista con movimientos) --
ALTER TABLE vino
    DROP CONSTRAINT fk_vino_bodega,
    ADD  CONSTRAINT fk_vino_bodega FOREIGN KEY (id_bodega)
         REFERENCES bodega (id_bodega) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE lote_de_uva
    DROP CONSTRAINT fk_lote_bodega,
    ADD  CONSTRAINT fk_lote_bodega FOREIGN KEY (id_bodega_entrega)
         REFERENCES bodega (id_bodega) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE ingreso
    DROP CONSTRAINT fk_ingreso_transportista,
    ADD  CONSTRAINT fk_ingreso_transportista FOREIGN KEY (id_transportista)
         REFERENCES transportista (id_transportista) ON DELETE RESTRICT ON UPDATE RESTRICT,
    DROP CONSTRAINT fk_ingreso_bodega,
    ADD  CONSTRAINT fk_ingreso_bodega FOREIGN KEY (id_bodega)
         REFERENCES bodega (id_bodega) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE renglon_ingreso
    DROP CONSTRAINT fk_renglon_ingreso_vino,
    ADD  CONSTRAINT fk_renglon_ingreso_vino FOREIGN KEY (id_vino)
         REFERENCES vino (id_vino) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE renglon_transferencia
    DROP CONSTRAINT fk_renglon_transf_vino,
    ADD  CONSTRAINT fk_renglon_transf_vino FOREIGN KEY (id_vino)
         REFERENCES vino (id_vino) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE detalle_comprobante
    DROP CONSTRAINT fk_detalle_vino,
    ADD  CONSTRAINT fk_detalle_vino FOREIGN KEY (id_vino)
         REFERENCES vino (id_vino) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE stock_sala
    DROP CONSTRAINT fk_stock_sala_vino,
    ADD  CONSTRAINT fk_stock_sala_vino FOREIGN KEY (id_vino)
         REFERENCES vino (id_vino) ON DELETE RESTRICT ON UPDATE RESTRICT,
    DROP CONSTRAINT fk_stock_sala_sala,
    ADD  CONSTRAINT fk_stock_sala_sala FOREIGN KEY (id_sala)
         REFERENCES sala_de_ventas (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE stock_deposito
    DROP CONSTRAINT fk_stock_deposito_vino,
    ADD  CONSTRAINT fk_stock_deposito_vino FOREIGN KEY (id_vino)
         REFERENCES vino (id_vino) ON DELETE RESTRICT ON UPDATE RESTRICT;

-- La auditoría no debe perderse: un vino con historial de precios no se borra.
ALTER TABLE auditoria_precio
    DROP CONSTRAINT fk_auditoria_vino,
    ADD  CONSTRAINT fk_auditoria_vino FOREIGN KEY (id_vino)
         REFERENCES vino (id_vino) ON DELETE RESTRICT ON UPDATE RESTRICT;

-- 2.c  RESTRICT: cabeceras de movimientos ----------------------------
ALTER TABLE comprobante
    DROP CONSTRAINT fk_comprobante_cliente,
    ADD  CONSTRAINT fk_comprobante_cliente FOREIGN KEY (id_cliente)
         REFERENCES cliente (id_cliente) ON DELETE RESTRICT ON UPDATE RESTRICT,
    DROP CONSTRAINT fk_comprobante_sala,
    ADD  CONSTRAINT fk_comprobante_sala FOREIGN KEY (id_sala)
         REFERENCES sala_de_ventas (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE transferencia
    DROP CONSTRAINT fk_transferencia_sala,
    ADD  CONSTRAINT fk_transferencia_sala FOREIGN KEY (id_sala)
         REFERENCES sala_de_ventas (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT;

-- 2.d  CASCADE: filas que no existen sin su cabecera -----------------
-- Renglones de documentos
ALTER TABLE renglon_ingreso
    DROP CONSTRAINT fk_renglon_ingreso_ingreso,
    ADD  CONSTRAINT fk_renglon_ingreso_ingreso FOREIGN KEY (id_ingreso)
         REFERENCES ingreso (id_ingreso) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE renglon_transferencia
    DROP CONSTRAINT fk_renglon_transf_transferencia,
    ADD  CONSTRAINT fk_renglon_transf_transferencia FOREIGN KEY (id_transferencia)
         REFERENCES transferencia (id_transferencia) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE detalle_comprobante
    DROP CONSTRAINT fk_detalle_comprobante,
    ADD  CONSTRAINT fk_detalle_comprobante FOREIGN KEY (id_comprobante)
         REFERENCES comprobante (id_comprobante) ON DELETE CASCADE ON UPDATE RESTRICT;

-- Composición y maridajes forman parte de la ficha del vino
ALTER TABLE vino_cepa
    DROP CONSTRAINT fk_vino_cepa_vino,
    ADD  CONSTRAINT fk_vino_cepa_vino FOREIGN KEY (id_vino)
         REFERENCES vino (id_vino) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE vino_maridaje
    DROP CONSTRAINT fk_vino_maridaje_vino,
    ADD  CONSTRAINT fk_vino_maridaje_vino FOREIGN KEY (id_vino)
         REFERENCES vino (id_vino) ON DELETE CASCADE ON UPDATE RESTRICT;

-- Atributos multivaluados y cobertura del transportista
-- (si el transportista tiene ingresos, la FK de ingreso igual impide borrarlo)
ALTER TABLE transportista_email
    DROP CONSTRAINT fk_email_transportista,
    ADD  CONSTRAINT fk_email_transportista FOREIGN KEY (id_transportista)
         REFERENCES transportista (id_transportista) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE transportista_telefono
    DROP CONSTRAINT fk_telefono_transportista,
    ADD  CONSTRAINT fk_telefono_transportista FOREIGN KEY (id_transportista)
         REFERENCES transportista (id_transportista) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE transportista_localidad
    DROP CONSTRAINT fk_tl_transportista,
    ADD  CONSTRAINT fk_tl_transportista FOREIGN KEY (id_transportista)
         REFERENCES transportista (id_transportista) ON DELETE CASCADE ON UPDATE RESTRICT;

-- Subtipos de cliente (jerarquía supertipo + subtipos) y permisos del exportador
-- (si el cliente tiene comprobantes, la FK de comprobante igual impide borrarlo)
ALTER TABLE socio
    DROP CONSTRAINT fk_socio_cliente,
    ADD  CONSTRAINT fk_socio_cliente FOREIGN KEY (id_cliente)
         REFERENCES cliente (id_cliente) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE distribuidor
    DROP CONSTRAINT fk_distribuidor_cliente,
    ADD  CONSTRAINT fk_distribuidor_cliente FOREIGN KEY (id_cliente)
         REFERENCES cliente (id_cliente) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE exportador
    DROP CONSTRAINT fk_exportador_cliente,
    ADD  CONSTRAINT fk_exportador_cliente FOREIGN KEY (id_cliente)
         REFERENCES cliente (id_cliente) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE permiso_exportacion
    DROP CONSTRAINT fk_permiso_exportador,
    ADD  CONSTRAINT fk_permiso_exportador FOREIGN KEY (id_cliente)
         REFERENCES exportador (id_cliente) ON DELETE CASCADE ON UPDATE RESTRICT;

-- Entidad débil: la parcela no existe sin su finca
-- (si la parcela tiene lotes, la FK de lote_de_uva igual impide borrarla)
ALTER TABLE parcela
    DROP CONSTRAINT fk_parcela_finca,
    ADD  CONSTRAINT fk_parcela_finca FOREIGN KEY (id_finca)
         REFERENCES finca (id_finca) ON DELETE CASCADE ON UPDATE RESTRICT;

-- Los análisis de calidad pertenecen al lote
ALTER TABLE analisis_calidad
    DROP CONSTRAINT fk_analisis_lote,
    ADD  CONSTRAINT fk_analisis_lote FOREIGN KEY (id_lote_uva)
         REFERENCES lote_de_uva (id_lote_uva) ON DELETE CASCADE ON UPDATE RESTRICT;


-- ---------------------------------------------------------------------
-- 3. UNIQUE adicionales (definidos en el esquema relacional, Etapa 1)
-- ---------------------------------------------------------------------
-- Un departamento no se repite dentro de la misma provincia
ALTER TABLE departamento
    ADD CONSTRAINT uq_departamento_nombre_provincia UNIQUE (nombre, provincia);

-- RN-04: una parcela se cosecha a lo sumo una vez por campaña
ALTER TABLE lote_de_uva
    ADD CONSTRAINT uq_lote_parcela_campania UNIQUE (id_finca, num_parcela, campania);

-- Mismo nombre comercial sólo con distinta añada o presentación
ALTER TABLE vino
    ADD CONSTRAINT uq_vino_nombre_anada_presentacion UNIQUE (nombre_comercial, anada, presentacion_ml);

-- Un documento identifica a un único cliente
ALTER TABLE cliente
    ADD CONSTRAINT uq_cliente_documento UNIQUE (tipo_documento, num_documento);

-- Un vino aparece una sola vez por ingreso / por transferencia
ALTER TABLE renglon_ingreso
    ADD CONSTRAINT uq_renglon_ingreso_vino UNIQUE (id_ingreso, id_vino);

ALTER TABLE renglon_transferencia
    ADD CONSTRAINT uq_renglon_transferencia_vino UNIQUE (id_transferencia, id_vino);


-- ---------------------------------------------------------------------
-- 4. CHECK
-- ---------------------------------------------------------------------
-- RN-01: el precio de un vino es siempre mayor que cero
-- (dom_dinero sólo exige >= 0; acá se exige > 0)
ALTER TABLE vino
    ADD CONSTRAINT ck_vino_precio_positivo CHECK (precio_venta > 0);

-- RN-15: la graduación alcohólica está entre 5 y 20
ALTER TABLE vino
    ADD CONSTRAINT ck_vino_graduacion CHECK (graduacion_alcoholica BETWEEN 5 AND 20);

-- Presentaciones habituales (Anexo B.4 de la consigna)
ALTER TABLE vino
    ADD CONSTRAINT ck_vino_presentacion CHECK (presentacion_ml IN (187, 375, 750, 1500, 3000));

-- Añada razonable (rango fijo: no se usa CURRENT_DATE en un CHECK)
ALTER TABLE vino
    ADD CONSTRAINT ck_vino_anada CHECK (anada BETWEEN 1900 AND 2100);

-- RN-15: superficies positivas
ALTER TABLE finca
    ADD CONSTRAINT ck_finca_superficie CHECK (sup_total_ha > 0);

ALTER TABLE parcela
    ADD CONSTRAINT ck_parcela_superficie CHECK (superficie > 0);

-- RN-15: kilos cosechados positivos
ALTER TABLE lote_de_uva
    ADD CONSTRAINT ck_lote_kilos CHECK (kilos_cosechados > 0);

-- CHECK ENTRE COLUMNAS: la campaña es el año de la fecha de cosecha
ALTER TABLE lote_de_uva
    ADD CONSTRAINT ck_lote_campania_fecha CHECK (EXTRACT(YEAR FROM fecha_cosecha) = campania);

-- RN-07 - CHECK ENTRE COLUMNAS: el vencimiento es posterior a la emisión
ALTER TABLE permiso_exportacion
    ADD CONSTRAINT ck_permiso_fechas CHECK (fecha_vencimiento > fecha_emision);

-- RN-15: cantidades positivas en los renglones
-- (dom_cantidad admite 0 porque se usa también para el stock)
ALTER TABLE renglon_ingreso
    ADD CONSTRAINT ck_renglon_ingreso_cantidad CHECK (cantidad_botellas > 0);

ALTER TABLE renglon_transferencia
    ADD CONSTRAINT ck_renglon_transferencia_cantidad CHECK (cantidad_botellas > 0);

ALTER TABLE detalle_comprobante
    ADD CONSTRAINT ck_detalle_cantidad CHECK (cantidad > 0);

-- RN-15: precio de venta del renglón positivo
ALTER TABLE detalle_comprobante
    ADD CONSTRAINT ck_detalle_precio CHECK (precio_unitario_venta > 0);

-- RN-08 - CHECK ENTRE COLUMNAS: total = subtotal - descuento
ALTER TABLE comprobante
    ADD CONSTRAINT ck_comprobante_importes
    CHECK (descuento <= subtotal AND total = subtotal - descuento);

-- Salario positivo
ALTER TABLE empleado
    ADD CONSTRAINT ck_empleado_salario CHECK (salario > 0);

-- pH dentro de la escala química
ALTER TABLE analisis_calidad
    ADD CONSTRAINT ck_analisis_ph CHECK (ph BETWEEN 0 AND 14);

-- Nota RN-09: "el stock nunca es negativo" ya lo garantiza el dominio
-- dom_cantidad (CHECK VALUE >= 0) de stock_sala.cantidad y
-- stock_deposito.cantidad. RN-06 (rango del descuento) lo garantiza el
-- dominio dom_porcentaje (CHECK VALUE BETWEEN 0 AND 100).


-- ---------------------------------------------------------------------
-- 5. DEFAULT
-- ---------------------------------------------------------------------
-- Estado inicial de los documentos
ALTER TABLE ingreso       ALTER COLUMN estado SET DEFAULT 'en_confeccion';
ALTER TABLE transferencia ALTER COLUMN estado SET DEFAULT 'en_confeccion';

-- Fechas que por defecto son la actual
ALTER TABLE ingreso       ALTER COLUMN fecha            SET DEFAULT CURRENT_DATE;
ALTER TABLE transferencia ALTER COLUMN fecha_confeccion SET DEFAULT CURRENT_DATE;
ALTER TABLE cliente       ALTER COLUMN fecha_alta       SET DEFAULT CURRENT_DATE;
ALTER TABLE comprobante   ALTER COLUMN fecha            SET DEFAULT CURRENT_DATE;

-- Los importes del comprobante arrancan en 0 y los calculan los triggers (RN-08)
ALTER TABLE comprobante ALTER COLUMN subtotal  SET DEFAULT 0;
ALTER TABLE comprobante ALTER COLUMN descuento SET DEFAULT 0;
ALTER TABLE comprobante ALTER COLUMN total     SET DEFAULT 0;

-- Auditoría: fecha/hora y usuario de la sesión (RN-13)
ALTER TABLE auditoria_precio ALTER COLUMN fecha_hora SET DEFAULT now();
ALTER TABLE auditoria_precio ALTER COLUMN usuario    SET DEFAULT session_user;

-- Stock nuevo arranca en 0
ALTER TABLE stock_sala     ALTER COLUMN cantidad SET DEFAULT 0;
ALTER TABLE stock_deposito ALTER COLUMN cantidad SET DEFAULT 0;
