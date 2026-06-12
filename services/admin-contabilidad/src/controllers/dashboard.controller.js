const reportesService = require('../services/reportes.service');

const getDashboard = async (req, res) => {
    try {
        const { inicio, fin} = req.query;

        const ventas = await reportesService.getVentas(inicio, fin);
        const pedidos = await reportesService.getPedidos(inicio, fin);
        const propinas = await reportesService.getPropinas(inicio, fin);
        const costos = await reportesService.getCostos(inicio, fin);

        const totalVentas = Number(ventas.total_ventas);
        const totalPedidos = Number(pedidos.total_pedidos);
        const totalPropinas = Number(propinas.total_propinas);
        const totalCostos = Number(costos.total_costos);

        res.json({
            ventas: totalVentas,
            pedidos: totalPedidos,
            propinas: totalPropinas,
            costos: totalCostos,
            ganancia: totalVentas - totalCostos
        });
    } catch (error) {
        console.error({
            mensaje: error.message,
            stack: error.stack
        });        
        res.status(500).json({error:'Error en dashboard'});
    }
};

module.exports = {
    getDashboard
};