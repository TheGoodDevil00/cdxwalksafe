import networkx as nx
from app.services.risk_engine import RiskEngine
from typing import List, Dict, Tuple
import math

class RoutingService:
    def __init__(self):
        self.risk_engine = RiskEngine()
        self.graph = nx.Graph()
        # Mock Graph for demonstration
        # In production, this would load from PostGIS/pgRouting or cache
        self._build_mock_graph()

    def _build_mock_graph(self):
        # A simple grid-like graph
        # Node (Grid X, Grid Y)
        # Edges with various properties
        points = [(0,0), (0,1), (0,2), (1,0), (1,1), (1,2), (2,0), (2,1), (2,2)]
        for idx, p in enumerate(points):
            self.graph.add_node(idx, lat=p[0], lon=p[1])

        # Add edges (ID, node1, node2, distance, lighting, base_risk)
        edges = [
            (0, 1, 100, 0.2, 0.0), # Safe street
            (1, 2, 100, 0.8, 0.0), # Dark alley
            (0, 3, 100, 0.5, 0.0),
            (3, 4, 100, 0.5, 0.0),
            (4, 5, 100, 0.2, 0.0),
            (1, 4, 140, 0.3, 0.0), # Diagonal
            (4, 7, 100, 0.9, 0.8), # Dangerous spot
            (7, 8, 100, 0.5, 0.0),
            (5, 8, 100, 0.4, 0.0),
            (2, 5, 100, 0.2, 0.0)
        ]
        
        for u, v, dist, lighting, risk in edges:
            self.graph.add_edge(u, v, 
                distance=dist, 
                lighting_score=lighting, 
                base_risk_score=risk,
                object_id=f"{u}-{v}"
            )

    def get_route(self, start_node: int, end_node: int, mode: str = 'balanced') -> Dict:
        """
        Mode: 'fastest', 'safest', 'balanced'
        """
        
        def weight_function(u, v, d):
            edge_data = self.graph[u][v]
            distance = edge_data.get('distance', 1.0)
            
            if mode == 'fastest':
                return distance
            
            risk = self.risk_engine.calculate_edge_risk(edge_data)
            
            if mode == 'safest':
                # Risk acts as a massive multiplier to distance
                # Effectively minimizing accumulated risk * distance
                return distance * (1 + risk * 100)
            
            if mode == 'balanced':
                return distance * (1 + risk * 5)
                
            return distance

        try:
            path_nodes = nx.shortest_path(self.graph, source=start_node, target=end_node, weight=weight_function)
            
            # Reconstruct path details
            path_coords = []
            total_risk = 0.0
            total_dist = 0.0
            
            for i in range(len(path_nodes)-1):
                u, v = path_nodes[i], path_nodes[i+1]
                edge = self.graph[u][v]
                node_data = self.graph.nodes[u]
                path_coords.append({"lat": node_data['lat'], "lon": node_data['lon']})
                
                total_dist += edge.get('distance', 0)
                total_risk += self.risk_engine.calculate_edge_risk(edge)
            
            # Add last node
            last_node = self.graph.nodes[path_nodes[-1]]
            path_coords.append({"lat": last_node['lat'], "lon": last_node['lon']})

            return {
                "path": path_coords,
                "total_distance": total_dist,
                "average_safety_score": 1.0 - (total_risk / max(len(path_nodes)-1, 1)) # Normalize roughly
            }
        except nx.NetworkXNoPath:
            return None

routing_service = RoutingService()
