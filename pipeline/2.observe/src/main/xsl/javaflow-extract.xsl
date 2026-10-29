<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:map="http://www.w3.org/2005/xpath-functions/map"
                xmlns:jf="urn:java-flow"
                exclude-result-prefixes="xs map jf"
                expand-text="yes">
    <xsl:output method="xml" indent="yes" encoding="UTF-8"/>
    <xsl:strip-space elements="*"/>
    <xsl:mode on-no-match="shallow-skip"/>

    <xsl:function name="jf:clean-text" as="xs:string">
        <xsl:param name="n" as="node()?"/>
        <xsl:sequence select="normalize-space(string($n))"/>
    </xsl:function>

    <xsl:function name="jf:identifier-chain" as="xs:string">
        <xsl:param name="n" as="element()?"/>
        <xsl:sequence select="string-join($n//r[@name='identifier']/t[@type='IDENTIFIER']/normalize-space(.), '.')"/>
    </xsl:function>

    <xsl:function name="jf:qualified-name" as="xs:string">
        <xsl:param name="n" as="element()?"/>
        <xsl:sequence select="jf:identifier-chain($n)"/>
    </xsl:function>

    <xsl:function name="jf:type-name" as="xs:string">
        <xsl:param name="typeType" as="element()?"/>
        <xsl:variable name="classType" as="xs:string"
                      select="jf:clean-text(($typeType//r[@name='classType'][1]//r[@name='typeIdentifier'][1]/t[@type='IDENTIFIER'])[1])"/>
        <xsl:variable name="primitiveType" as="xs:string"
                      select="lower-case(jf:clean-text(($typeType//r[@name='primitiveType'][1]/t)[1]))"/>
        <xsl:sequence select="if ($classType ne '') then $classType else $primitiveType"/>
    </xsl:function>

    <xsl:function name="jf:created-name" as="xs:string">
        <xsl:param name="creator" as="element()?"/>
        <xsl:sequence select="jf:identifier-chain($creator/r[@name='createdName'][1])"/>
    </xsl:function>

    <xsl:function name="jf:resolve-type" as="xs:string">
        <xsl:param name="shortName" as="xs:string?"/>
        <xsl:param name="packageName" as="xs:string"/>
        <xsl:param name="imports" as="map(xs:string, xs:string)"/>
        <xsl:variable name="name" select="normalize-space($shortName)" as="xs:string"/>
        <xsl:sequence select="
            if ($name = '') then ''
            else if (contains($name, '.')) then $name
            else if (map:contains($imports, $name)) then $imports($name)
            else if ($name = ('byte','short','int','long','float','double','boolean','char','void','var')) then ''
            else if ($packageName ne '') then $packageName || '.' || $name
            else $name"/>
    </xsl:function>

    <xsl:function name="jf:receiver-name" as="xs:string">
        <xsl:param name="expr" as="element(r)"/>
        <xsl:sequence select="jf:clean-text(($expr/r[@name='expression'][1]/r[@name='primary'][1]/r[@name='identifier'][1]/t[@type='IDENTIFIER'])[1])"/>
    </xsl:function>

    <xsl:function name="jf:method-name" as="xs:string">
        <xsl:param name="expr" as="element(r)"/>
        <xsl:sequence select="jf:clean-text(($expr/r[@name='methodCall'][1]/r[@name='identifier'][1]/t[@type='IDENTIFIER'])[1])"/>
    </xsl:function>

    <xsl:function name="jf:line-no" as="xs:string">
        <xsl:param name="expr" as="element(r)"/>
        <xsl:sequence select="string(($expr/r[@name='methodCall'][1]//t[@type='IDENTIFIER'][1]/@line)[1])"/>
    </xsl:function>

    <xsl:template match="/ast">
        <xsl:variable name="packageName" as="xs:string"
                      select="jf:qualified-name((.//r[@name='packageDeclaration']/r[@name='qualifiedName'])[1])"/>
        <xsl:variable name="className" as="xs:string"
                      select="jf:clean-text((.//r[@name='classDeclaration'][1]/r[@name='identifier'][1]/t[@type='IDENTIFIER'])[1])"/>
        <xsl:variable name="sourceClass" as="xs:string"
                      select="if ($packageName ne '' and $className ne '') then $packageName || '.' || $className else $className"/>

        <xsl:variable name="imports" as="map(xs:string, xs:string)">
            <xsl:map>
                <xsl:for-each select=".//r[@name='importDeclaration'][not(t[@type='MUL'])]">
                    <xsl:variable name="fqn" as="xs:string" select="jf:qualified-name(r[@name='qualifiedName'][1])"/>
                    <xsl:if test="$fqn ne ''">
                        <xsl:map-entry key="tokenize($fqn, '\.')[last()]" select="$fqn"/>
                    </xsl:if>
                </xsl:for-each>
            </xsl:map>
        </xsl:variable>

        <xsl:variable name="fieldVarTypes" as="map(xs:string, xs:string)">
            <xsl:map>
                <xsl:for-each-group select=".//r[@name='fieldDeclaration']//r[@name='variableDeclaratorId']/r[@name='identifier']/t[@type='IDENTIFIER']"
                                    group-by="normalize-space(.)">
                    <xsl:variable name="declaration" as="element(r)?"
                                  select="current-group()[last()]/ancestor::r[@name='fieldDeclaration'][1]"/>
                    <xsl:variable name="resolvedType" as="xs:string"
                                  select="jf:resolve-type(jf:type-name($declaration/r[@name='typeType'][1]), $packageName, $imports)"/>
                    <xsl:if test="$resolvedType ne '' and current-grouping-key() ne ''">
                        <xsl:map-entry key="current-grouping-key()" select="$resolvedType"/>
                    </xsl:if>
                </xsl:for-each-group>
            </xsl:map>
        </xsl:variable>

        <xsl:variable name="localVarTypes" as="map(xs:string, xs:string)">
            <xsl:map>
                <xsl:for-each-group select=".//r[@name='localVariableDeclaration'][r[@name='typeType']]//r[@name='variableDeclaratorId']/r[@name='identifier']/t[@type='IDENTIFIER']"
                                    group-by="normalize-space(.)">
                    <xsl:variable name="declaration" as="element(r)?"
                                  select="current-group()[last()]/ancestor::r[@name='localVariableDeclaration'][1]"/>
                    <xsl:variable name="resolvedType" as="xs:string"
                                  select="jf:resolve-type(jf:type-name($declaration/r[@name='typeType'][1]), $packageName, $imports)"/>
                    <xsl:if test="$resolvedType ne '' and current-grouping-key() ne ''">
                        <xsl:map-entry key="current-grouping-key()" select="$resolvedType"/>
                    </xsl:if>
                </xsl:for-each-group>
            </xsl:map>
        </xsl:variable>

        <xsl:variable name="parameterVarTypes" as="map(xs:string, xs:string)">
            <xsl:map>
                <xsl:for-each-group select=".//r[@name='formalParameter']//r[@name='variableDeclaratorId']/r[@name='identifier']/t[@type='IDENTIFIER']"
                                    group-by="normalize-space(.)">
                    <xsl:variable name="declaration" as="element(r)?"
                                  select="current-group()[last()]/ancestor::r[@name='formalParameter'][1]"/>
                    <xsl:variable name="resolvedType" as="xs:string"
                                  select="jf:resolve-type(jf:type-name($declaration/r[@name='typeType'][1]), $packageName, $imports)"/>
                    <xsl:if test="$resolvedType ne '' and current-grouping-key() ne ''">
                        <xsl:map-entry key="current-grouping-key()" select="$resolvedType"/>
                    </xsl:if>
                </xsl:for-each-group>
            </xsl:map>
        </xsl:variable>

        <xsl:variable name="inferredVarTypesFromNew" as="map(xs:string, xs:string)">
            <xsl:map>
                <xsl:for-each-group select=".//r[@name='variableDeclarator'][r[@name='variableInitializer']//r[@name='creator']]//r[@name='variableDeclaratorId']/r[@name='identifier']/t[@type='IDENTIFIER']"
                                    group-by="normalize-space(.)">
                    <xsl:variable name="declaration" as="element(r)?"
                                  select="current-group()[last()]/ancestor::r[@name='variableDeclarator'][1]"/>
                    <xsl:variable name="createdName" as="xs:string"
                                  select="jf:created-name(($declaration/r[@name='variableInitializer']//r[@name='creator'])[1])"/>
                    <xsl:variable name="resolvedType" as="xs:string"
                                  select="jf:resolve-type($createdName, $packageName, $imports)"/>
                    <xsl:if test="$resolvedType ne '' and current-grouping-key() ne ''">
                        <xsl:map-entry key="current-grouping-key()" select="$resolvedType"/>
                    </xsl:if>
                </xsl:for-each-group>
            </xsl:map>
        </xsl:variable>

        <xsl:variable name="varTypes" as="map(xs:string, xs:string)"
                      select="map:merge(($fieldVarTypes, $localVarTypes, $parameterVarTypes, $inferredVarTypesFromNew), map{'duplicates':'use-first'})"/>

        <xsl:variable name="callEdges" as="map(*)*">
            <xsl:for-each select=".//r[@name='expression'][r[@name='methodCall'] and r[@name='expression'][1]/r[@name='primary']/r[@name='identifier']]">
                <xsl:variable name="receiverVar" as="xs:string" select="jf:receiver-name(.)"/>
                <xsl:variable name="methodName" as="xs:string" select="jf:method-name(.)"/>
                <xsl:variable name="lineNo" as="xs:string" select="jf:line-no(.)"/>
                <xsl:variable name="targetClass" as="xs:string"
                              select="
                                  if (map:contains($varTypes, $receiverVar)) then $varTypes($receiverVar)
                                  else
                                      let $resolved := jf:resolve-type($receiverVar, $packageName, $imports)
                                      return if ($resolved ne '') then $resolved else '__unresolved__.' || $receiverVar
                              "/>
                <xsl:if test="$sourceClass ne '' and $receiverVar ne '' and $methodName ne ''">
                    <xsl:sequence select="map{
                        'kind': 'method-call',
                        'source': $sourceClass,
                        'target': $targetClass,
                        'via': $receiverVar,
                        'method': $methodName,
                        'line': $lineNo
                    }"/>
                </xsl:if>
            </xsl:for-each>
        </xsl:variable>

        <xsl:variable name="internalCallEdges" as="map(*)*">
            <xsl:for-each select=".//r[@name='expression'][r[@name='methodCall'] and not(r[@name='expression'][1]/r[@name='primary']/r[@name='identifier'])]">
                <xsl:variable name="methodName" as="xs:string" select="jf:method-name(.)"/>
                <xsl:variable name="lineNo" as="xs:string" select="jf:line-no(.)"/>
                <xsl:if test="$sourceClass ne '' and $methodName ne ''">
                    <xsl:sequence select="map{
                        'kind': 'method-call',
                        'source': $sourceClass,
                        'target': $sourceClass,
                        'via': 'this',
                        'method': $methodName,
                        'line': $lineNo
                    }"/>
                </xsl:if>
            </xsl:for-each>
        </xsl:variable>

        <xsl:variable name="newEdges" as="map(*)*">
            <xsl:for-each select=".//r[@name='creator']">
                <xsl:variable name="createdRaw" as="xs:string" select="jf:created-name(.)"/>
                <xsl:variable name="lineNo" as="xs:string"
                              select="string(((preceding-sibling::t[@type='NEW'][1], ancestor::r[@name='expression'][1]/t[@type='NEW'][1])[1]/@line)[1])"/>
                <xsl:variable name="targetClass" as="xs:string"
                              select="if ($createdRaw ne '') then jf:resolve-type($createdRaw, $packageName, $imports) else ''"/>
                <xsl:if test="$sourceClass ne '' and $targetClass ne ''">
                    <xsl:sequence select="map{
                        'kind': 'instantiates',
                        'source': $sourceClass,
                        'target': $targetClass,
                        'via': '',
                        'method': '',
                        'line': $lineNo
                    }"/>
                </xsl:if>
            </xsl:for-each>
        </xsl:variable>

        <xsl:variable name="allEdges" as="map(*)*" select="($callEdges, $internalCallEdges, $newEdges)"/>
        <xsl:variable name="dedupEdges" as="map(*)*">
            <xsl:for-each-group select="$allEdges"
                                group-by="?kind || '|' || ?source || '|' || ?target || '|' || ?method || '|' || ?line">
                <xsl:sequence select="current-group()[1]"/>
            </xsl:for-each-group>
        </xsl:variable>

        <xsl:variable name="nodes" as="xs:string*" select="distinct-values(($sourceClass, $dedupEdges?target))"/>

        <flow-graph source="{@source}" package="{$packageName}" class="{$sourceClass}">
            <nodes>
                <xsl:for-each select="$nodes[. ne '']">
                    <xsl:sort select="."/>
                    <node id="{.}" kind="{if (. = $sourceClass) then 'source' else 'class'}"/>
                </xsl:for-each>
            </nodes>
            <edges>
                <xsl:for-each select="$dedupEdges">
                    <xsl:sort select="?kind"/>
                    <xsl:sort select="?source"/>
                    <xsl:sort select="?target"/>
                    <xsl:sort select="?method"/>
                    <edge kind="{?kind}"
                          source="{?source}"
                          target="{?target}"
                          method="{?method}"
                          via="{?via}"
                          line="{?line}"/>
                </xsl:for-each>
            </edges>
            <meta edgeCount="{count($dedupEdges)}" nodeCount="{count($nodes[. ne ''])}"/>
        </flow-graph>
    </xsl:template>
</xsl:stylesheet>
