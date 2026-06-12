-- ============================================================
--  SCHEMA COMPLETO - Admin y Contabilidad  (PostgreSQL 15+)
--  Sistema   : Pedidos Now
--  Modulo    : admin-contabilidad
--  Notas     : BIGSERIAL en todos los IDs, NUMERIC(18,2) en monetos,
--              TIMESTAMPTZ en fechas, indices en FK y columnas frecuentes.
--              movimiento_financiero particionado por trimestre.
-- ============================================================

-- Extensiones
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid(), crypt()
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- busqueda fuzzy en texto

-- ============================================================
--  FUNCION TRIGGER: updated_at automatico
-- ============================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- ============================================================
--  1. USUARIO
-- ============================================================
CREATE TABLE IF NOT EXISTS usuario (
    id            BIGSERIAL     PRIMARY KEY,
    nombre        VARCHAR(100)  NOT NULL,
    apellidos     VARCHAR(100)  NOT NULL,
    email         VARCHAR(150)  NOT NULL,
    password_hash TEXT          NOT NULL,
    tipo_usuario  VARCHAR(30)   NOT NULL DEFAULT 'admin'
                      CHECK (tipo_usuario IN ('admin','contador','supervisor','agente')),
    rol           VARCHAR(30)   NOT NULL DEFAULT 'viewer'
                      CHECK (rol IN ('admin','editor','viewer')),
    estado        VARCHAR(15)   NOT NULL DEFAULT 'activo'
                      CHECK (estado IN ('activo','inactivo','bloqueado')),
    telefono      VARCHAR(20),
    otros_datos   JSONB,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_usuario_email UNIQUE (email)
);

CREATE INDEX IF NOT EXISTS idx_usuario_email  ON usuario(email);
CREATE INDEX IF NOT EXISTS idx_usuario_estado ON usuario(estado);

CREATE TRIGGER trg_usuario_upd
    BEFORE UPDATE ON usuario
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE usuario IS 'Cuentas internas del modulo. La autenticacion usa JWT generado desde password_hash.';
COMMENT ON COLUMN usuario.tipo_usuario IS 'Rol funcional dentro del modulo (admin, contador, supervisor, agente).';
COMMENT ON COLUMN usuario.otros_datos  IS 'Datos adicionales flexibles en JSONB (preferencias, metadata de integracion, etc).';

-- ============================================================
--  2. ENTIDAD COMERCIAL
-- ============================================================
-- entidad_id_externo es el ID del microservicio de Negocios (sin FK inter-servicio)
CREATE TABLE IF NOT EXISTS entidad_comercial (
    id                 BIGSERIAL     PRIMARY KEY,
    entidad_id_externo BIGINT        NOT NULL,
    nombre_comercial   VARCHAR(150)  NOT NULL,
    tipo               VARCHAR(30)   NOT NULL DEFAULT 'negocio'
                           CHECK (tipo IN ('negocio','restaurante','paqueteria','otro')),
    activo             BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_entidad_externa UNIQUE (entidad_id_externo, tipo)
);

CREATE INDEX IF NOT EXISTS idx_entidad_ext  ON entidad_comercial(entidad_id_externo);
CREATE INDEX IF NOT EXISTS idx_entidad_tipo ON entidad_comercial(tipo);

COMMENT ON TABLE entidad_comercial IS 'Espejo local de negocios/restaurantes/paqueterias para reportes contables.';
COMMENT ON COLUMN entidad_comercial.entidad_id_externo IS 'ID del recurso en el microservicio origen. No hay FK por ser inter-servicio.';

-- ============================================================
--  3. CUENTA FONDO
-- ============================================================
-- Un fondo por tipo. Saldo nunca puede ser negativo.
CREATE TABLE IF NOT EXISTS cuenta_fondo (
    id                 BIGSERIAL     PRIMARY KEY,
    nombre             VARCHAR(100)  NOT NULL,
    tipo               VARCHAR(30)   NOT NULL
                           CHECK (tipo IN ('reembolsos','compensaciones','pagos_agentes','general')),
    saldo              NUMERIC(18,2) NOT NULL DEFAULT 0.00 CHECK (saldo >= 0),
    cuenta_bancaria_id BIGINT,
    descripcion        TEXT,
    created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_cuenta_fondo_tipo UNIQUE (tipo)
);

CREATE TRIGGER trg_fondo_upd
    BEFORE UPDATE ON cuenta_fondo
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE cuenta_fondo IS 'Fondos internos para reembolsos, compensaciones y pagos a agentes.';
COMMENT ON COLUMN cuenta_fondo.saldo IS 'Saldo actual del fondo. Constraint CHECK garantiza que nunca sea negativo.';

-- ============================================================
--  4. MOVIMIENTO FINANCIERO  (tabla central, PARTICIONADA por trimestre)
-- ============================================================
-- subtipo: pedido, reembolso, compensacion, pago_agente, cancelacion
-- referencia_id: ID del objeto que genero el movimiento
-- NOTA: La PK compuesta (id, fecha) es obligatoria para particionamiento por rango.
CREATE TABLE IF NOT EXISTS movimiento_financiero (
    id                   BIGSERIAL     NOT NULL,
    cuenta_id            BIGINT        REFERENCES cuenta_fondo(id) ON DELETE SET NULL,
    tipo                 VARCHAR(10)   NOT NULL CHECK (tipo IN ('ingreso','egreso')),
    subtipo              VARCHAR(40)   NOT NULL,
    modulo_origen        VARCHAR(50)   NOT NULL,
    referencia_id        BIGINT,
    monto                NUMERIC(18,2) NOT NULL CHECK (monto > 0),
    descripcion          TEXT,
    pedido_id            BIGINT,
    repartidor_id        BIGINT,
    estado               VARCHAR(15)   NOT NULL DEFAULT 'procesado'
                             CHECK (estado IN ('pendiente','procesado','anulado')),
    transaction_id_banco VARCHAR(100),
    payment_id_cobros    VARCHAR(100),
    idempotency_key      VARCHAR(100),
    fecha                DATE          NOT NULL DEFAULT CURRENT_DATE,
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT pk_movimiento PRIMARY KEY (id, fecha)
) PARTITION BY RANGE (fecha);

-- Particiones trimestrales 2026
CREATE TABLE IF NOT EXISTS movimiento_financiero_2026_q1
    PARTITION OF movimiento_financiero FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');

CREATE TABLE IF NOT EXISTS movimiento_financiero_2026_q2
    PARTITION OF movimiento_financiero FOR VALUES FROM ('2026-04-01') TO ('2026-07-01');

CREATE TABLE IF NOT EXISTS movimiento_financiero_2026_q3
    PARTITION OF movimiento_financiero FOR VALUES FROM ('2026-07-01') TO ('2026-10-01');

CREATE TABLE IF NOT EXISTS movimiento_financiero_2026_q4
    PARTITION OF movimiento_financiero FOR VALUES FROM ('2026-10-01') TO ('2027-01-01');

-- Particion de desbordamiento: captura todo lo posterior a 2026
CREATE TABLE IF NOT EXISTS movimiento_financiero_futuro
    PARTITION OF movimiento_financiero FOR VALUES FROM ('2027-01-01') TO (MAXVALUE);

CREATE INDEX IF NOT EXISTS idx_mv_cuenta      ON movimiento_financiero(cuenta_id);
CREATE INDEX IF NOT EXISTS idx_mv_tipo        ON movimiento_financiero(tipo, subtipo);
CREATE INDEX IF NOT EXISTS idx_mv_fecha       ON movimiento_financiero(fecha DESC);
CREATE INDEX IF NOT EXISTS idx_mv_pedido      ON movimiento_financiero(pedido_id);
CREATE INDEX IF NOT EXISTS idx_mv_repartidor  ON movimiento_financiero(repartidor_id);
CREATE INDEX IF NOT EXISTS idx_mv_pendiente   ON movimiento_financiero(estado) WHERE estado = 'pendiente';
-- En tablas particionadas el UNIQUE debe incluir la columna de particion (fecha)
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_idempotency
    ON movimiento_financiero(idempotency_key, fecha)
    WHERE idempotency_key IS NOT NULL;

COMMENT ON TABLE movimiento_financiero IS 'Tabla central de contabilidad. Particionada por trimestre para escala. Agregar particion cada ano con: CREATE TABLE movimiento_financiero_YYYY_qN PARTITION OF movimiento_financiero FOR VALUES FROM (...) TO (...).';
COMMENT ON COLUMN movimiento_financiero.idempotency_key IS 'Clave unica para prevenir movimientos duplicados en reintentos.';

-- ============================================================
--  5. PEDIDO CONTABILIDAD
-- ============================================================
-- Espejo contable de pedidos para reportes por entidad comercial.
CREATE TABLE IF NOT EXISTS pedido_contabilidad (
    id                   BIGSERIAL     PRIMARY KEY,
    entidad_comercial_id BIGINT        REFERENCES entidad_comercial(id) ON DELETE SET NULL,
    pedido_id_externo    BIGINT        NOT NULL,
    tipo_pedido          VARCHAR(30)   NOT NULL DEFAULT 'normal'
                             CHECK (tipo_pedido IN ('normal','express','programado','paqueteria')),
    modulo_origen        VARCHAR(50)   NOT NULL,
    subtotal             NUMERIC(18,2) NOT NULL DEFAULT 0,
    descuento            NUMERIC(18,2) NOT NULL DEFAULT 0,
    comision             NUMERIC(18,2) NOT NULL DEFAULT 0,
    total                NUMERIC(18,2) NOT NULL DEFAULT 0,
    estado               VARCHAR(20)   NOT NULL DEFAULT 'pendiente'
                             CHECK (estado IN ('pendiente','completado','cancelado','reembolsado')),
    fecha                DATE          NOT NULL DEFAULT CURRENT_DATE,
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_pedido_externo UNIQUE (pedido_id_externo, modulo_origen)
);

CREATE INDEX IF NOT EXISTS idx_pc_entidad ON pedido_contabilidad(entidad_comercial_id);
CREATE INDEX IF NOT EXISTS idx_pc_fecha   ON pedido_contabilidad(fecha DESC);
CREATE INDEX IF NOT EXISTS idx_pc_estado  ON pedido_contabilidad(estado);

COMMENT ON TABLE pedido_contabilidad IS 'Registro contable de pedidos por entidad comercial. pedido_id_externo no tiene FK (inter-servicio).';

-- ============================================================
--  6. COBRO
-- ============================================================
-- Cobros a clientes. idempotency_key previene duplicados en reintentos.
CREATE TABLE IF NOT EXISTS cobro (
    id                    BIGSERIAL     PRIMARY KEY,
    cliente_id            BIGINT        NOT NULL,
    pedido_id             BIGINT        NOT NULL,
    repartidor_id         BIGINT,
    cupon_id              BIGINT,
    monto_total           NUMERIC(18,2) NOT NULL CHECK (monto_total >= 0),
    tarifa_servicio       NUMERIC(18,2) NOT NULL DEFAULT 0,
    propina               NUMERIC(18,2) NOT NULL DEFAULT 0,
    tipo_pago             VARCHAR(15)   NOT NULL CHECK (tipo_pago IN ('efectivo','tarjeta','cupon')),
    estado                VARCHAR(15)   NOT NULL DEFAULT 'pendiente'
                              CHECK (estado IN ('pendiente','procesando','completado','denegado','cancelado')),
    numero_transaccion    VARCHAR(100),
    idempotency_key       VARCHAR(100)  NOT NULL,
    estado_reconciliacion VARCHAR(15)   NOT NULL DEFAULT 'pendiente'
                              CHECK (estado_reconciliacion IN ('pendiente','reconciliado','discrepancia')),
    payment_id_cobros     VARCHAR(100),
    transaction_id_banco  VARCHAR(100),
    ultimo_error_externo  TEXT,
    reconciliado          BOOLEAN       NOT NULL DEFAULT FALSE,
    fecha_cobro           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_cobro_idempotency UNIQUE (idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_cobro_cliente    ON cobro(cliente_id);
CREATE INDEX IF NOT EXISTS idx_cobro_pedido     ON cobro(pedido_id);
CREATE INDEX IF NOT EXISTS idx_cobro_repartidor ON cobro(repartidor_id);
CREATE INDEX IF NOT EXISTS idx_cobro_estado     ON cobro(estado);
CREATE INDEX IF NOT EXISTS idx_cobro_fecha      ON cobro(fecha_cobro DESC);
-- Indice parcial: solo cobros no reconciliados (minimiza tamanio del indice)
CREATE INDEX IF NOT EXISTS idx_cobro_recon      ON cobro(estado_reconciliacion) WHERE reconciliado = FALSE;

CREATE TRIGGER trg_cobro_upd
    BEFORE UPDATE ON cobro
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE cobro IS 'Cobros a clientes. idempotency_key previene duplicados. Indice parcial en reconciliados = FALSE para el worker de conciliacion.';
COMMENT ON COLUMN cobro.ultimo_error_externo IS 'Ultimo mensaje de error del proveedor de pagos externo. Util para soporte.';

-- ============================================================
--  7. COBRO DENEGADO
-- ============================================================
CREATE TABLE IF NOT EXISTS cobro_denegado (
    id              BIGSERIAL     PRIMARY KEY,
    cliente_id      BIGINT        NOT NULL,
    pedido_id       BIGINT        NOT NULL,
    repartidor_id   BIGINT,
    monto_intentado NUMERIC(18,2) NOT NULL,
    razon           VARCHAR(255)  NOT NULL,
    tipo_pago       VARCHAR(15)   NOT NULL,
    fecha_intento   TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cd_cliente ON cobro_denegado(cliente_id);
CREATE INDEX IF NOT EXISTS idx_cd_pedido  ON cobro_denegado(pedido_id);
CREATE INDEX IF NOT EXISTS idx_cd_fecha   ON cobro_denegado(fecha_intento DESC);

COMMENT ON TABLE cobro_denegado IS 'Intentos de cobro fallidos. Util para analisis de fraude y atencion al cliente.';

-- ============================================================
--  8. COBRO CANCELADO
-- ============================================================
-- ON DELETE CASCADE: si el cobro se elimina, la cancelacion pierde sentido.
CREATE TABLE IF NOT EXISTS cobro_cancelado (
    id                BIGSERIAL     PRIMARY KEY,
    cobro_id          BIGINT        NOT NULL REFERENCES cobro(id) ON DELETE CASCADE,
    razon             VARCHAR(255)  NOT NULL,
    reembolsado       BOOLEAN       NOT NULL DEFAULT FALSE,
    monto_reembolso   NUMERIC(18,2) NOT NULL DEFAULT 0,
    fecha_cancelacion TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cc_cobro ON cobro_cancelado(cobro_id);
CREATE INDEX IF NOT EXISTS idx_cc_fecha ON cobro_cancelado(fecha_cancelacion DESC);

COMMENT ON TABLE cobro_cancelado IS 'Cancelaciones de cobros completados. Puede disparar reembolso al cliente.';

-- ============================================================
--  9. REEMBOLSO CLIENTE
-- ============================================================
-- usuario_ref_id es ID del cliente en el microservicio de usuarios (sin FK inter-servicio).
CREATE TABLE IF NOT EXISTS reembolso_cliente (
    id                BIGSERIAL     PRIMARY KEY,
    usuario_ref_id    BIGINT        NOT NULL,
    pedido_id_externo BIGINT,
    cobro_id          BIGINT        REFERENCES cobro(id) ON DELETE SET NULL,
    movimiento_id     BIGINT,
    motivo            VARCHAR(255)  NOT NULL,
    monto             NUMERIC(18,2) NOT NULL CHECK (monto > 0),
    estado            VARCHAR(15)   NOT NULL DEFAULT 'pendiente'
                          CHECK (estado IN ('pendiente','aprobado','rechazado','procesado')),
    notas             TEXT,
    created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rc_usuario ON reembolso_cliente(usuario_ref_id);
CREATE INDEX IF NOT EXISTS idx_rc_cobro   ON reembolso_cliente(cobro_id);
CREATE INDEX IF NOT EXISTS idx_rc_estado  ON reembolso_cliente(estado);

CREATE TRIGGER trg_reembolso_upd
    BEFORE UPDATE ON reembolso_cliente
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE reembolso_cliente IS 'Reembolsos a clientes por pedidos cancelados o cobros incorrectos.';
COMMENT ON COLUMN reembolso_cliente.usuario_ref_id IS 'ID del cliente en el microservicio de Usuarios. Sin FK por ser inter-servicio.';

-- ============================================================
--  10. COMPENSACION ENTIDAD
-- ============================================================
CREATE TABLE IF NOT EXISTS compensacion_entidad (
    id                   BIGSERIAL     PRIMARY KEY,
    entidad_comercial_id BIGINT        REFERENCES entidad_comercial(id) ON DELETE SET NULL,
    movimiento_id        BIGINT,
    motivo               VARCHAR(255)  NOT NULL,
    monto                NUMERIC(18,2) NOT NULL CHECK (monto > 0),
    estado               VARCHAR(15)   NOT NULL DEFAULT 'aprobado'
                             CHECK (estado IN ('pendiente','aprobado','rechazado','procesado')),
    notas                TEXT,
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_comp_entidad ON compensacion_entidad(entidad_comercial_id);
CREATE INDEX IF NOT EXISTS idx_comp_estado  ON compensacion_entidad(estado);

CREATE TRIGGER trg_comp_upd
    BEFORE UPDATE ON compensacion_entidad
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE compensacion_entidad IS 'Compensaciones economicas a entidades comerciales por fallas de servicio.';

-- ============================================================
--  11. EVENTO SISTEMA
-- ============================================================
-- Indice GIN en payload permite buscar dentro del JSONB sin cambiar el schema.
CREATE TABLE IF NOT EXISTS evento_sistema (
    id            BIGSERIAL   PRIMARY KEY,
    modulo_origen VARCHAR(50) NOT NULL,
    tipo_evento   VARCHAR(80) NOT NULL,
    referencia_id BIGINT,
    payload       JSONB,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ev_modulo  ON evento_sistema(modulo_origen);
CREATE INDEX IF NOT EXISTS idx_ev_tipo    ON evento_sistema(tipo_evento);
CREATE INDEX IF NOT EXISTS idx_ev_ref     ON evento_sistema(referencia_id);
CREATE INDEX IF NOT EXISTS idx_ev_fecha   ON evento_sistema(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ev_payload ON evento_sistema USING GIN (payload);

COMMENT ON TABLE evento_sistema IS 'Log de eventos de negocio. El indice GIN en payload permite buscar campos JSONB sin cambiar el schema.';

-- ============================================================
--  12. AUDITORIA FINANCIERA
-- ============================================================
-- Solo INSERT, nunca UPDATE/DELETE. metadata guarda estado anterior/posterior.
CREATE TABLE IF NOT EXISTS auditoria_financiera (
    id             BIGSERIAL     PRIMARY KEY,
    usuario_id     BIGINT        REFERENCES usuario(id) ON DELETE SET NULL,
    accion         VARCHAR(80)   NOT NULL,
    tabla_afectada VARCHAR(60),
    registro_id    BIGINT,
    descripcion    TEXT,
    monto          NUMERIC(18,2),
    metadata       JSONB,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_aud_usuario ON auditoria_financiera(usuario_id);
CREATE INDEX IF NOT EXISTS idx_aud_accion  ON auditoria_financiera(accion);
CREATE INDEX IF NOT EXISTS idx_aud_tabla   ON auditoria_financiera(tabla_afectada, registro_id);
CREATE INDEX IF NOT EXISTS idx_aud_fecha   ON auditoria_financiera(created_at DESC);

COMMENT ON TABLE auditoria_financiera IS 'Auditoria financiera. Solo INSERT. metadata guarda estado anterior/posterior en JSONB.';
COMMENT ON COLUMN auditoria_financiera.metadata IS 'JSON con campos {antes: {...}, despues: {...}} para trazabilidad completa.';

-- ============================================================
--  13. CHAT RESOLUCION FINANCIERA
-- ============================================================
-- Recibe casos del microservicio de Chats via webhook POST /api/chats/resolucion.
-- reembolso_id y compensacion_id se llenan al procesar (PATCH /resoluciones/:id/procesar).
CREATE TABLE IF NOT EXISTS chat_resolucion_financiera (
    id               BIGSERIAL   PRIMARY KEY,
    conversation_id  CHAR(36)    NOT NULL,
    tipo_resolucion  VARCHAR(30) NOT NULL
                         CHECK (tipo_resolucion IN ('RESOLVED_REFUND','RESOLVED_COUPON','RESOLVED_NO_SOLUTION','CLOSED_MANUAL')),
    requester_type   VARCHAR(20) NOT NULL CHECK (requester_type IN ('CUSTOMER','COURIER','BUSINESS')),
    requester_ext_id VARCHAR(64) NOT NULL,
    case_type        VARCHAR(20) NOT NULL DEFAULT 'OTHER'
                         CHECK (case_type IN ('ORDER','DELIVERY','BUSINESS_CASE','OTHER')),
    case_reference   VARCHAR(64),
    movimiento_id    BIGINT,
    reembolso_id     BIGINT      REFERENCES reembolso_cliente(id) ON DELETE SET NULL,
    compensacion_id  BIGINT      REFERENCES compensacion_entidad(id) ON DELETE SET NULL,
    estado           VARCHAR(15) NOT NULL DEFAULT 'pendiente'
                         CHECK (estado IN ('pendiente','procesado','rechazado')),
    notas            TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_chat_conversation UNIQUE (conversation_id)
);

CREATE INDEX IF NOT EXISTS idx_crf_estado    ON chat_resolucion_financiera(estado);
CREATE INDEX IF NOT EXISTS idx_crf_tipo      ON chat_resolucion_financiera(tipo_resolucion);
CREATE INDEX IF NOT EXISTS idx_crf_ref       ON chat_resolucion_financiera(case_reference);
CREATE INDEX IF NOT EXISTS idx_crf_requester ON chat_resolucion_financiera(requester_type, requester_ext_id);

CREATE TRIGGER trg_chat_res_upd
    BEFORE UPDATE ON chat_resolucion_financiera
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE chat_resolucion_financiera IS 'Casos financieros del microservicio de Chats. reembolso_id/compensacion_id se llenan al procesar con PATCH /resoluciones/:id/procesar.';
COMMENT ON COLUMN chat_resolucion_financiera.conversation_id IS 'UUID de la conversacion en el servicio de Chats. UNIQUE garantiza idempotencia del webhook.';

-- ============================================================
--  14. CHAT ESTADISTICA PERIODO
-- ============================================================
-- Generado desde GET /api/chats/estadisticas. UNIQUE en periodo para evitar duplicados.
CREATE TABLE IF NOT EXISTS chat_estadistica_periodo (
    id                     BIGSERIAL     PRIMARY KEY,
    periodo_inicio         DATE          NOT NULL,
    periodo_fin            DATE          NOT NULL,
    total_conversaciones   INT           NOT NULL DEFAULT 0,
    resueltas_reembolso    INT           NOT NULL DEFAULT 0,
    resueltas_cupon        INT           NOT NULL DEFAULT 0,
    resueltas_sin_solucion INT           NOT NULL DEFAULT 0,
    cerradas_timeout       INT           NOT NULL DEFAULT 0,
    cerradas_manual        INT           NOT NULL DEFAULT 0,
    monto_reembolsado      NUMERIC(18,2) NOT NULL DEFAULT 0,
    monto_compensado       NUMERIC(18,2) NOT NULL DEFAULT 0,
    reporte_id             BIGINT,
    generated_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_chat_periodo UNIQUE (periodo_inicio, periodo_fin)
);

CREATE INDEX IF NOT EXISTS idx_cep_periodo ON chat_estadistica_periodo(periodo_inicio, periodo_fin);

COMMENT ON TABLE chat_estadistica_periodo IS 'Estadisticas de chats por periodo. Generado desde GET /api/chats/estadisticas. UNIQUE evita duplicados por periodo.';

-- ============================================================
--  15. CHAT LLAMADA LOG
-- ============================================================
-- Indice parcial en http_status >= 400 para diagnostico rapido de errores.
CREATE TABLE IF NOT EXISTS chat_llamada_log (
    id              BIGSERIAL    PRIMARY KEY,
    metodo          VARCHAR(10)  NOT NULL,
    endpoint        VARCHAR(255) NOT NULL,
    conversation_id CHAR(36),
    payload         JSONB,
    http_status     SMALLINT,
    respuesta       JSONB,
    duracion_ms     INT,
    error_mensaje   TEXT,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cll_conversation ON chat_llamada_log(conversation_id);
CREATE INDEX IF NOT EXISTS idx_cll_fecha        ON chat_llamada_log(created_at DESC);
-- Indice parcial: solo errores HTTP. Minimiza tamanio del indice.
CREATE INDEX IF NOT EXISTS idx_cll_errores      ON chat_llamada_log(http_status) WHERE http_status >= 400;

COMMENT ON TABLE chat_llamada_log IS 'Log HTTP de llamadas al microservicio de Chats. Indice parcial en http_status >= 400 para diagnostico rapido.';

-- ============================================================
--  16. MIGRATIONS
-- ============================================================
-- Nunca eliminar filas. Es el historial de cambios aplicados.
CREATE TABLE IF NOT EXISTS migrations (
    id          SERIAL       PRIMARY KEY,
    filename    VARCHAR(255) NOT NULL UNIQUE,
    executed_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE migrations IS 'Control de migraciones SQL ejecutadas. Nunca borrar filas — es el historial de cambios.';

-- ============================================================
--  DATOS INICIALES
-- ============================================================
INSERT INTO cuenta_fondo (nombre, tipo, descripcion) VALUES
    ('Fondo de Reembolsos',     'reembolsos',     'Fondo para reembolsos a clientes'),
    ('Fondo de Compensaciones', 'compensaciones', 'Fondo para compensaciones a entidades comerciales'),
    ('Fondo Pagos Agentes',     'pagos_agentes',  'Fondo para nomina de agentes de soporte'),
    ('Fondo General',           'general',        'Fondo general de operaciones')
ON CONFLICT (tipo) DO NOTHING;

-- ============================================================
--  VISTAS
-- ============================================================

-- Saldo por fondo con ingresos y egresos historicos
CREATE OR REPLACE VIEW v_saldo_fondos AS
SELECT
    cf.id,
    cf.nombre,
    cf.tipo,
    cf.saldo                                                              AS saldo_actual,
    COALESCE(SUM(CASE WHEN mf.tipo = 'ingreso' THEN mf.monto ELSE 0 END), 0) AS total_ingresos,
    COALESCE(SUM(CASE WHEN mf.tipo = 'egreso'  THEN mf.monto ELSE 0 END), 0) AS total_egresos
FROM cuenta_fondo cf
LEFT JOIN movimiento_financiero mf
       ON mf.cuenta_id = cf.id AND mf.estado = 'procesado'
GROUP BY cf.id, cf.nombre, cf.tipo, cf.saldo;

COMMENT ON VIEW v_saldo_fondos IS 'Saldo de cada fondo con ingresos y egresos historicos calculados desde movimientos procesados.';

-- Casos de chat pendientes ordenados por antiguedad (para que el agente priorice)
CREATE OR REPLACE VIEW v_chat_resoluciones_pendientes AS
SELECT
    crf.id,
    crf.conversation_id,
    crf.tipo_resolucion,
    crf.requester_type,
    crf.requester_ext_id,
    crf.case_type,
    crf.case_reference,
    crf.created_at,
    ROUND(EXTRACT(EPOCH FROM (NOW() - crf.created_at)) / 3600, 1) AS horas_pendiente
FROM chat_resolucion_financiera crf
WHERE crf.estado = 'pendiente'
ORDER BY crf.created_at ASC;

COMMENT ON VIEW v_chat_resoluciones_pendientes IS 'Casos de chat pendientes de procesamiento, ordenados por antiguedad. horas_pendiente ayuda a priorizar.';

-- Resumen de cobros del dia actual
CREATE OR REPLACE VIEW v_cobros_hoy AS
SELECT
    tipo_pago,
    estado,
    COUNT(*)         AS cantidad,
    SUM(monto_total) AS monto_total
FROM cobro
WHERE fecha_cobro::DATE = CURRENT_DATE
GROUP BY tipo_pago, estado;

COMMENT ON VIEW v_cobros_hoy IS 'Resumen de cobros del dia en curso agrupado por tipo de pago y estado.';
